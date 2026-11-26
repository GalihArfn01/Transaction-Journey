import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/model/analytics_math.dart' show comparePeriods;
import '../../core/utils/finance_math.dart';
import '../../core/utils/money_formatter.dart';
import '../../core/utils/period.dart';
import '../../data/datasource/app_database.dart';
import '../../data/datasource/dao/transaction_dao.dart';
import '../../domain/model/enums.dart';
import '../../app/app_theme.dart' show FinanceColors;
import '../analytics/analytics_providers.dart' show monthlySeriesProvider;
import '../../core/utils/balance_privacy.dart';
import '../../data/datasource/database_provider.dart';
import '../settings/hide_balance_controller.dart';
import '../shared/app_icons.dart';
import '../shared/controllers/period_selection.dart';
import '../shared/widgets/empty_state.dart';
import '../shared/widgets/gradient_app_bar.dart';
import '../shared/widgets/animations.dart';
import '../shared/widgets/app_card.dart';
import '../shared/widgets/colorful_3d_chip.dart';
import 'dashboard_providers.dart';

final DateFormat _dayMonthYearFormat = DateFormat('d MMM y', 'id_ID');

/// Label waktu relatif: 'Hari ini, HH:mm' / 'Kemarin, HH:mm' / tanggal.
String _relativeTimeLabel(DateTime d) {
  final DateTime now = DateTime.now();
  final DateTime day = DateTime(d.year, d.month, d.day);
  final DateTime today = DateTime(now.year, now.month, now.day);
  final int diffDays = today.difference(day).inDays;
  final String hm = DateFormat('HH:mm').format(d);
  if (diffDays == 0) return 'Hari ini, $hm';
  if (diffDays == 1) return 'Kemarin, $hm';
  return _dayMonthYearFormat.format(d);
}

/// Ringkasan Keuangan — desain bento dari
/// docs/design_references/dashboard_reference.html: hero Total Saldo
/// (fold saldo rekening + badge tren bulanan), sub-card pemasukan/
/// pengeluaran, Saving Rate bar, Analisis Pengeluaran top-5, dan
/// Transaksi Terbaru dengan waktu relatif.
class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key, this.onSeeAllTransactions});

  /// Wiring navigasi 'Lihat Semua' dilakukan A saat merge.
  final VoidCallback? onSeeAllTransactions;

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      // Transparan: latar putih milik lapisan STATIS `AppShell` supaya
      // tidak ikut bergeser/memudar saat pindah tab (lihat `AppShell`).
      backgroundColor: Colors.transparent,
      appBar: GradientAppBar(
        title: 'Ringkasan Keuangan',
        actions: [
          IconButton(
            tooltip: 'Rentang kustom',
            icon: const Icon(Icons.calendar_today_outlined),
            onPressed: () => _pickCustomRange(context, ref),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          // Streams drift sudah reaktif; tarik-untuk-segar hanya jeda UX.
          await Future<void>.delayed(const Duration(milliseconds: 300));
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 96),
          children: <Widget>[
            // Kartu muncul SATU PER SATU dari atas (stagger) begitu masuk
            // layar, sehingga halaman terasa "terakit" — bukan berkedip
            // sekaligus. Reveal-nya MENGULANG saat kartu digulir keluar
            // lalu masuk lagi, dan saat tab Dashboard dibuka kembali
            // (RevealScope dari AppShell).
            const ScrollReveal(child: _PeriodChips()),
            const ScrollReveal(
              delay: Duration(milliseconds: 30),
              child: _BentoHero(),
            ),
            const ScrollReveal(
              delay: Duration(milliseconds: 60),
              child: _ExpenseBreakdown(),
            ),
            ScrollReveal(
              delay: const Duration(milliseconds: 90),
              child: _LatestTransactions(onSeeAll: onSeeAllTransactions),
            ),
          ],
        ),
      ),
    );
  }
}

/// Chips periode 3D senada tema: tombol 3D biru primary untuk yang
/// terpilih, putih berbingkai biru untuk sisanya — lengkap dengan ikon
/// kalender per periode. Label & perilaku tap dipertahankan persis.
class _PeriodChips extends ConsumerWidget {
  const _PeriodChips();

  static const List<_PeriodChipSpec> _specs = <_PeriodChipSpec>[
    _PeriodChipSpec(
      type: PeriodType.today,
      label: 'Hari',
      icon: Icons.today_outlined,
    ),
    _PeriodChipSpec(
      type: PeriodType.thisWeek,
      label: 'Minggu',
      icon: Icons.calendar_view_week_outlined,
    ),
    _PeriodChipSpec(
      type: PeriodType.thisMonth,
      label: 'Bulan',
      icon: Icons.calendar_month_outlined,
    ),
    _PeriodChipSpec(
      type: PeriodType.thisYear,
      label: 'Tahun',
      icon: Icons.event_outlined,
    ),
    _PeriodChipSpec(
      type: PeriodType.all,
      label: 'Semua',
      icon: Icons.select_all_outlined,
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PeriodSelection selection = ref.watch(periodSelectionProvider);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: <Widget>[
          for (final _PeriodChipSpec spec in _specs)
            Padding(
              padding: const EdgeInsets.only(right: 10, bottom: 6),
              child: Colorful3DChip(
                label: spec.label,
                icon: spec.icon,
                selected: selection.type == spec.type,
                onTap: () => ref
                    .read(periodSelectionProvider.notifier)
                    .select(spec.type),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 10, bottom: 6),
            child: Colorful3DChip(
              label: 'Kustom',
              icon: Icons.tune,
              selected: selection.type == PeriodType.custom,
              onTap: () async {
                final DateTimeRange? picked = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (picked != null && context.mounted) {
                  ref
                      .read(periodSelectionProvider.notifier)
                      .selectCustom(picked.start, picked.end);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Spesifikasi satu chip periode: kunci provider, label, ikon.
class _PeriodChipSpec {
  const _PeriodChipSpec({
    required this.type,
    required this.label,
    required this.icon,
  });

  final PeriodType type;
  final String label;
  final IconData icon;
}

/// Seksi hero: Total Saldo mandiri ([AppCard.hero]), lalu SATU grup
/// "Arus Kas" ([AppCard.group]) berisi sepasang Pemasukan/Pengeluaran +
/// Saving Rate — ketiganya sejenis (label + angka + bar) sehingga pantas
/// satu wadah berdivider, bukan tiga kartu terpisah.
class _BentoHero extends ConsumerWidget {
  const _BentoHero();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<AccountWithBalance>? balances =
        ref.watch(accountBalancesProvider).valueOrNull;
    final PeriodTotals? totals = ref.watch(periodTotalsProvider).valueOrNull;

    final int totalBalanceMinor = (balances ?? const <AccountWithBalance>[])
        .fold<int>(0, (int sum, AccountWithBalance r) => sum + r.balanceMinor);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _TotalBalanceCard(totalMinor: totalBalanceMinor),
          const SizedBox(height: 12),
          AppCard.group(
            title: 'Arus Kas',
            children: <Widget>[
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(
                      child: _FlowStat(
                        label: 'Pemasukan',
                        amountMinor: totals?.incomeMinor ?? 0,
                        icon: Icons.south_west,
                        containerColor:
                            FinanceColors.income.withValues(alpha: 0.12),
                        valueColor: FinanceColors.income,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _FlowStat(
                        label: 'Pengeluaran',
                        amountMinor: totals?.expenseMinor ?? 0,
                        icon: Icons.north_east,
                        containerColor: Theme.of(context)
                            .colorScheme
                            .error
                            .withValues(alpha: 0.1),
                        valueColor: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ),
              ),
              _SavingRateContent(totals: totals),
            ],
          ),
        ],
      ),
    );
  }
}

class _TotalBalanceCard extends ConsumerWidget {
  const _TotalBalanceCard({required this.totalMinor});

  final int totalMinor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;
    final bool hidden = ref.watch(hideBalanceProvider).valueOrNull ?? false;

    // Badge tren NET bulan ini vs bulan lalu dari deret 12 bulan.
    // Sembunyikan bila data < 2 titik atau previous == 0 (persen tak
    // terdefinisi).
    double? trendPercent;
    final List<MonthSeriesPoint>? series =
        ref.watch(monthlySeriesProvider).valueOrNull;
    if (series != null && series.length >= 2) {
      final MonthSeriesPoint previous = series[series.length - 2];
      final MonthSeriesPoint current = series.last;
      if (previous.netMinor != 0) {
        trendPercent =
            comparePeriods(current.netMinor, previous.netMinor).percentChange;
      }
    }

    // Hero migrasi ke AppCard.hero: gradient, radius, shadow & clip
    // identik — hanya pembungkusnya yang kini dari bahasa kartu bersama.
    return AppCard.hero(
      padding: EdgeInsets.zero,
      child: Stack(
        children: <Widget>[
          const Align(
            alignment: Alignment.topRight,
            child: FractionalTranslation(
              translation: Offset(0.25, -0.25),
              child: _DecorCircle(size: 128),
            ),
          ),
          const Align(
            alignment: Alignment.bottomLeft,
            child: FractionalTranslation(
              translation: Offset(-0.2, 0.2),
              child: _DecorCircle(size: 96),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: SizedBox(
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Text(
                        'Total Saldo',
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.onPrimary.withValues(alpha: 0.9),
                        ),
                      ),
                      const Spacer(),
                      InkResponse(
                        key: const Key('hide_balance_toggle'),
                        radius: 20,
                        onTap: () => setHideBalance(
                          ref.read(appDatabaseProvider),
                          !hidden,
                        ),
                        child: Tooltip(
                          message:
                              hidden ? 'Tampilkan saldo' : 'Sembunyikan saldo',
                          child: Icon(
                            hidden
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            size: 22,
                            color: scheme.onPrimary.withValues(alpha: 0.9),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  FittedBox(
                    // Angka terpenting di seluruh app: beri label semantik
                    // eksplisit agar TalkBack membacanya utuh, bukan potongan.
                    child: Semantics(
                      label: hidden
                          ? 'Total saldo disembunyikan'
                          : 'Total saldo ${MoneyFormatter.format(totalMinor)}',
                      excludeSemantics: true,
                      // "Rp" STATIS di luar animasi — hanya angka / titik
                      // penyamar yang di-cross-fade saat tombol mata
                      // ditekan.
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: <Widget>[
                          Text(
                            'Rp',
                            style: textTheme.displaySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: scheme.onPrimary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            switchInCurve: kSharedMotionCurve,
                            switchOutCurve: Curves.easeInCubic,
                            // Rata KIRI (default AnimatedSwitcher = tengah):
                            // angka & titik yang lebarnya beda tetap mulai
                            // di posisi yang sama, tepat setelah "Rp".
                            layoutBuilder:
                                (Widget? current, List<Widget> previous) =>
                                    Stack(
                              alignment: Alignment.centerLeft,
                              children: <Widget>[
                                ...previous,
                                if (current != null) current,
                              ],
                            ),
                            child: hidden
                                ? Text(
                                    kHiddenBalanceDigits,
                                    key: const ValueKey<String>(
                                        'balance_hidden'),
                                    style: textTheme.displaySmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: scheme.onPrimary,
                                    ),
                                  )
                                // Angka hero "dihitung naik" (count-up).
                                : AnimatedAmountText(
                                    key:
                                        const ValueKey<String>('balance_value'),
                                    valueMinor: totalMinor,
                                    withSymbol: false,
                                    style: textTheme.displaySmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: scheme.onPrimary,
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (trendPercent != null)
                    _TrendRow(trendPercent: trendPercent),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Baris badge tren "+x.x% vs bulan lalu" (diekstrak dari hero agar
/// struktur build tetap ramping).
class _TrendRow extends StatelessWidget {
  const _TrendRow({required this.trendPercent});

  final double trendPercent;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Row(
        children: <Widget>[
          Icon(
            trendPercent >= 0 ? Icons.trending_up : Icons.trending_down,
            size: 20,
            color: scheme.onPrimary,
          ),
          const SizedBox(width: 6),
          Text(
            '${trendPercent >= 0 ? '+' : ''}'
            '${trendPercent.toStringAsFixed(1)}% vs bulan lalu',
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onPrimary.withValues(alpha: 0.95),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}


/// Lingkaran putih opacity 5 persen sebagai dekorasi hero.
class _DecorCircle extends StatelessWidget {
  const _DecorCircle({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          shape: BoxShape.circle,
        ),
      );
}

/// Stat Pemasukan/Pengeluaran TANPA bingkai kartu — hidup di dalam grup
/// "Arus Kas" ([AppCard.group]), jadi bingkai & bayangannya milik grup.
/// Isi (ikon, label, nominal count-up) dipertahankan persis.
class _FlowStat extends StatelessWidget {
  const _FlowStat({
    required this.label,
    required this.amountMinor,
    required this.icon,
    required this.containerColor,
    required this.valueColor,
  });

  final String label;
  final int amountMinor;
  final IconData icon;
  final Color containerColor;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: containerColor,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 22, color: valueColor),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              FittedBox(
                // Ikut "dihitung naik" seperti hero di atasnya.
                child: AnimatedAmountText(
                  valueMinor: amountMinor,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: valueColor,
                      ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Isi Saving Rate TANPA bingkai kartu — anak kedua grup "Arus Kas".
/// Perhitungan & tampilan dipertahankan persis.
class _SavingRateContent extends StatelessWidget {
  const _SavingRateContent({required this.totals});

  final PeriodTotals? totals;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final double? rate = totals == null
        ? null
        : savingRate(
            income: totals!.incomeMinor,
            expense: totals!.expenseMinor,
          );

    return Row(
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child:
              Icon(Icons.savings_outlined, size: 22, color: scheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text(
                    'Saving Rate',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  Text(
                    rate == null ? '-' : '${rate.toStringAsFixed(1)}%',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              AnimatedProgressBar(
                value: rate == null ? 0 : (rate / 100).clamp(0.0, 1.0),
                backgroundColor: scheme.surfaceContainerHighest,
                color: scheme.primary,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Palet fallback untuk kategori tanpa warna kustom — dipakai berurutan
/// supaya tiap potongan donut tetap gampang dibedakan.
const List<Color> _fallbackSliceColors = <Color>[
  FinanceColors.expense,
  Color(0xFFB2622C),
  Color(0xFF8B5CF6),
  Color(0xFF0B57A4),
  Color(0xFF0D9488),
];

/// Analisis Pengeluaran: donut chart top-5 kategori + sisanya digabung
/// jadi "Lainnya", dengan legenda (titik warna, nama, nominal, persen)
/// di bawahnya.
class _ExpenseBreakdown extends ConsumerStatefulWidget {
  const _ExpenseBreakdown();

  @override
  ConsumerState<_ExpenseBreakdown> createState() => _ExpenseBreakdownState();
}

class _ExpenseBreakdownState extends ConsumerState<_ExpenseBreakdown> {
  int? _touchedIndex;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<CategorySlice>> slices =
        ref.watch(categorySlicesProvider(TransactionType.expense));

    // SEBELUMNYA kartu ini dibuat FULL-BLEED (menempel kiri-kanan layar,
    // radius & border kiri-kanan dihapus) atas permintaan pengguna waktu
    // itu — sekarang diminta balik supaya UKURANNYA SAMA dengan kartu
    // "Transaksi Terbaru" di bawahnya: margin horizontal 16 (bukan penuh
    // layar), border 4 sisi, dan borderRadius 16, persis meniru
    // `_LatestTransactions` (termasuk `EdgeInsets.fromLTRB(16, 20, 16, 0)`
    // di pembungkusnya, judul, dan `clipBehavior: Clip.antiAlias`) supaya
    // dua kartu itu terlihat sebagai satu keluarga desain yang konsisten.
    // Judul kartu berada DI DALAM kartu (bukan melayang di atasnya).
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: AppCard.standard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Analisis Pengeluaran',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            slices.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(12),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (Object e, StackTrace _) => Text('Gagal memuat: $e'),
              data: (List<CategorySlice> list) {
                if (list.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Belum ada pengeluaran pada periode ini.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  );
                }

                final ColorScheme scheme = Theme.of(context).colorScheme;
                final List<CategorySlice> top = list.take(5).toList();
                final int totalMinor = list.fold<int>(
                    0, (int sum, CategorySlice s) => sum + s.totalMinor);
                final int topMinor = top.fold<int>(
                    0, (int sum, CategorySlice s) => sum + s.totalMinor);
                final int otherMinor = totalMinor - topMinor;
                final double otherPercent =
                    totalMinor == 0 ? 0 : otherMinor / totalMinor * 100;

                // Entri legenda: 5 kategori teratas + "Lainnya" bila ada sisa.
                final List<_DonutEntry> entries = <_DonutEntry>[
                  for (int i = 0; i < top.length; i++)
                    _DonutEntry(
                      label: top[i].category.name,
                      icon: appIconForKey(top[i].category.icon),
                      amountMinor: top[i].totalMinor,
                      percent: top[i].percentOfTotal,
                      color: top[i].category.colorValue != null
                          ? Color(top[i].category.colorValue!)
                          : _fallbackSliceColors[
                              i % _fallbackSliceColors.length],
                    ),
                  if (otherMinor > 0)
                    _DonutEntry(
                      label: 'Lainnya',
                      icon: Icons.more_horiz,
                      amountMinor: otherMinor,
                      percent: otherPercent,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.35),
                    ),
                ];

                return Column(
                  children: <Widget>[
                    SizedBox(
                      height: 180,
                      child: Stack(
                        alignment: Alignment.center,
                        children: <Widget>[
                          // Donat "digambar" mengelilingi lingkaran: mulai
                          // dari jam 12 lalu berputar searah jarum jam
                          // sampai penuh (masker sweep, bukan ubah data —
                          // jadi animasi tap di bawah tetap utuh).
                          ChartSweepReveal(
                            child: PieChart(
                              // Transisi halus saat potongan di-tap (radius
                              // membesar) atau data kategori berganti.
                              duration: kChartDataAnimationDuration,
                              curve: kSharedMotionCurve,
                              PieChartData(
                                sectionsSpace: 2,
                                centerSpaceRadius: 52,
                                startDegreeOffset: -90,
                                pieTouchData: PieTouchData(
                                  touchCallback: (FlTouchEvent event,
                                      PieTouchResponse? response) {
                                    final int? index = response
                                        ?.touchedSection?.touchedSectionIndex;
                                    setState(() {
                                      _touchedIndex =
                                          (index == null || index < 0)
                                              ? null
                                              : index;
                                    });
                                  },
                                ),
                                sections: <PieChartSectionData>[
                                  for (int i = 0; i < entries.length; i++)
                                    PieChartSectionData(
                                      value: entries[i].percent <= 0
                                          ? 0.0001
                                          : entries[i].percent,
                                      // Potongan lain meredup saat salah satu
                                      // dipilih — pola yang sama dengan Top
                                      // Kategori Pengeluaran di halaman Analisis.
                                      color: entries[i].color.withValues(
                                            alpha: _touchedIndex == null ||
                                                    _touchedIndex == i
                                                ? 1
                                                : 0.3,
                                          ),
                                      radius: _touchedIndex == i ? 34 : 28,
                                      showTitle: false,
                                    ),
                                ],
                              ),
                            ),
                          ),
                          // Tap salah satu potongan donat -> label & nominal
                          // di tengah ikut berganti ke kategori yang dipilih
                          // (bukan cuma highlight radius seperti sebelumnya).
                          // Tap lagi (atau tap di luar potongan) -> balik
                          // ke total keseluruhan.
                          Builder(
                            builder: (BuildContext context) {
                              final _DonutEntry? selected =
                                  _touchedIndex != null &&
                                          _touchedIndex! < entries.length
                                      ? entries[_touchedIndex!]
                                      : null;
                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Text(
                                    selected?.label ?? 'Total',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                            color: scheme.onSurfaceVariant),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    MoneyFormatter.format(
                                      selected?.amountMinor ?? totalMinor,
                                    ),
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Column(
                      children: <Widget>[
                        for (int i = 0; i < entries.length; i++)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () => setState(
                                () => _touchedIndex =
                                    _touchedIndex == i ? null : i,
                              ),
                              child: Opacity(
                                opacity:
                                    _touchedIndex == null || _touchedIndex == i
                                        ? 1
                                        : 0.3,
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 4),
                                  child: Row(
                                    children: <Widget>[
                                      Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                          color: entries[i].color,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          entries[i].label,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Text(
                                        MoneyFormatter.format(
                                            entries[i].amountMinor),
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                                fontWeight: FontWeight.w700),
                                      ),
                                      const SizedBox(width: 8),
                                      SizedBox(
                                        width: 36,
                                        child: Text(
                                          '${entries[i].percent.toStringAsFixed(0)}%',
                                          textAlign: TextAlign.right,
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelMedium
                                              ?.copyWith(
                                                color: scheme.onSurfaceVariant,
                                              ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Baris legenda donut: label, ikon (tidak dipakai di legenda tapi
/// disimpan untuk konsistensi bila suatu saat legenda diberi ikon lagi),
/// nominal, persen, dan warna potongan.
class _DonutEntry {
  const _DonutEntry({
    required this.label,
    required this.icon,
    required this.amountMinor,
    required this.percent,
    required this.color,
  });

  final String label;
  final IconData icon;
  final int amountMinor;
  final double percent;
  final Color color;
}

class _LatestTransactions extends ConsumerWidget {
  const _LatestTransactions({required this.onSeeAll});

  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<TransactionWithRefs>> state =
        ref.watch(latestTransactionsProvider);

    // Judul kartu berada DI DALAM kartu (bukan melayang di atasnya).
    // Padding nol: padding dalam sudah diatur per-baris di bawah.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: AppCard.standard(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                onSeeAll != null ? 6 : 16,
                onSeeAll != null ? 4 : 16,
                onSeeAll != null ? 0 : 4,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text(
                    'Transaksi Terbaru',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  if (onSeeAll != null)
                    TextButton(
                      key: const Key('dashboard_see_all_button'),
                      onPressed: onSeeAll,
                      child: const Text('Lihat Semua'),
                    ),
                ],
              ),
            ),
            state.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (Object e, StackTrace _) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Gagal memuat: $e')),
              data: (List<TransactionWithRefs> items) {
                if (items.isEmpty) {
                  return const EmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'Belum ada transaksi',
                    message: 'Tekan tombol + untuk mulai mencatat.',
                  );
                }
                return Column(
                  children: <Widget>[
                    for (final TransactionWithRefs item in items)
                      _RecentTile(item: item),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentTile extends StatelessWidget {
  const _RecentTile({required this.item});

  final TransactionWithRefs item;

  @override
  Widget build(BuildContext context) {
    final Transaction tx = item.transaction;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    final Color amountColor = switch (tx.type) {
      TransactionType.income => FinanceColors.income,
      TransactionType.expense => FinanceColors.expense,
      TransactionType.transfer => FinanceColors.transfer,
    };

    final Color? categoryColor = item.category?.colorValue != null
        ? Color(item.category!.colorValue!)
        : null;

    final String title = switch (tx.type) {
      TransactionType.income ||
      TransactionType.expense =>
        tx.note?.trim().isNotEmpty == true
            ? tx.note!
            : item.category?.name ?? '(Tanpa kategori)',
      TransactionType.transfer =>
        '${item.account.name} -> ${item.toAccount?.name ?? '?'}',
    };

    final String amountText = switch (tx.type) {
      TransactionType.income => '+${MoneyFormatter.format(tx.amountMinor)}',
      TransactionType.expense => '-${MoneyFormatter.format(tx.amountMinor)}',
      TransactionType.transfer => MoneyFormatter.format(tx.amountMinor),
    };

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color:
              (categoryColor ?? scheme.onSurfaceVariant).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          appIconForKey(item.category?.icon),
          size: 22,
          color: categoryColor ?? scheme.onSurfaceVariant,
        ),
      ),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(_relativeTimeLabel(tx.date)),
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(
            amountText,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: amountColor,
            ),
          ),
          Text(
            item.account.name,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}
