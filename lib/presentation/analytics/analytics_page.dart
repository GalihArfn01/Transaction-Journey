import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_theme.dart' show FinanceColors;
import '../../core/utils/finance_math.dart';
import '../../core/utils/money_formatter.dart';
import '../../core/utils/period.dart';
import '../../data/datasource/dao/transaction_dao.dart';
import '../../domain/model/analytics_math.dart';
import '../../domain/model/enums.dart';
import '../dashboard/dashboard_providers.dart'
    show CategorySlice, categorySlicesProvider, periodTotalsProvider;
import '../shared/controllers/period_selection.dart';
import '../shared/widgets/animations.dart';
import '../shared/widgets/app_card.dart';
import '../shared/widgets/gradient_app_bar.dart';
import 'analytics_providers.dart';

/// Label periode konsisten dengan chip filter di halaman Dashboard
/// (`dashboard_page.dart`) — dipakai di sini supaya pengguna tahu rentang
/// waktu yang sedang berlaku untuk "Ringkasan" & "Top Kategori" TANPA
/// harus berpindah halaman untuk mengecek toggle Dashboard.
const Map<PeriodType, String> _periodLabels = <PeriodType, String>{
  PeriodType.today: 'Hari Ini',
  PeriodType.thisWeek: 'Minggu Ini',
  PeriodType.thisMonth: 'Bulan Ini',
  PeriodType.thisYear: 'Tahun Ini',
  PeriodType.custom: 'Rentang Kustom',
  PeriodType.all: 'Semua Waktu',
};

/// Halaman Analisis: ringkasan periode, tren 12 bulan, top kategori,
/// perbandingan bulan, forecast, dan skor kesehatan finansial.
///
/// Restyle W7 (pola Stitch docs/design_references/stitch_design_system.md):
/// kartu putih rounded-xl dengan soft shadow rgba(primary,5%), header
/// section headline-md, progress bar dinamis, spacing antar-section 40px.
/// Semua data lewat provider — TIDAK ada query langsung di widget.
class AnalyticsPage extends ConsumerWidget {
  const AnalyticsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      // Transparan: latar putih milik lapisan STATIS `AppShell` supaya
      // tidak ikut bergeser/memudar saat pindah tab (lihat `AppShell`).
      backgroundColor: Colors.transparent,
      appBar: const GradientAppBar(title: 'Analisis Keuangan'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        // Halaman ini PENDEK (7 kartu) tapi BERAT (2 chart fl_chart + kartu
        // stateful). ListView default membuang kartu yang jauh di luar
        // layar lalu MEMBANGUN ULANG-nya dari nol saat digulir kembali —
        // chart dibangun & dilukis ulang, reveal diputar ulang, dan state
        // kartu (bulan/kategori yang di-tap) hilang. Itulah frame macet
        // 34-60 ms yang terasa berat saat scroll (terukur dari rekaman
        // layar). cacheExtent besar menjaga SEMUA kartu tetap terbangun,
        // jadi menggulir hanya menggeser layer yang sudah jadi.
        cacheExtent: 4000,
        children: <Widget>[
          // Kartu muncul SATU PER SATU dari atas ke bawah saat halaman
          // dibuka dan saat tab Analisis dibuka kembali (RevealScope dari
          // AppShell) — TIDAK dipicu scroll (lihat ScrollReveal).
          const ScrollReveal(child: _PeriodBanner()),
          const SizedBox(height: 12),
          const ScrollReveal(
            delay: Duration(milliseconds: 25),
            child: _SummaryCards(),
          ),
          // Lima seksi analisis digabung dalam SATU grup ([AppCard.group])
          // — strukturnya homogen (judul + konten), jadi pantas satu wadah
          // berdivider, bukan lima kartu + lima bayangan. Satu reveal
          // untuk segrup (bukan per seksi) supaya tidak bertabrakan.
          const SizedBox(height: 40),
          const ScrollReveal(
            delay: Duration(milliseconds: 50),
            child: AppCard.group(
              children: <Widget>[
                _MonthlyTrendCard(),
                _TopCategoriesCard(),
                _MonthComparisonCard(),
                _ForecastCard(),
                _HealthScoreCard(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Chip kecil yang menunjukkan periode aktif ("Bulan Ini", dst).
///
/// SEBELUMNYA halaman ini TIDAK menampilkan info periode sama sekali,
/// padahal `_SummaryCards`, `_TopCategoriesCard`, dan komponen savingRate
/// di `_HealthScoreCard` semuanya mengikuti [periodSelectionProvider] —
/// kontroler GLOBAL yang dipakai bersama Dashboard & Riwayat (lihat
/// dokumentasi di `period_selection.dart`). Tanpa penanda ini, pengguna
/// yang mengubah filter di Dashboard (mis. ke "Minggu") lalu membuka
/// Analisis akan melihat angka ringkasan yang jauh lebih kecil dari
/// biasanya TANPA tahu alasannya — terlihat seperti bug padahal bukan.
///
/// CATATAN: kartu "Tren 12 Bulan", "Perbandingan Bulan", dan "Proyeksi"
/// di bawahnya SENGAJA TIDAK mengikuti periode ini (selalu 12 bulan
/// terakhir relatif hari ini) — makanya banner ini taruh tepat di atas
/// bagian yang benar-benar dipengaruhi filter, bukan di appbar.
class _PeriodBanner extends ConsumerWidget {
  const _PeriodBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PeriodSelection selection = ref.watch(periodSelectionProvider);
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final String label = _periodLabels[selection.type] ?? '-';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.date_range_outlined,
              size: 16, color: scheme.onSecondaryContainer),
          const SizedBox(width: 6),
          Text(
            'Ringkasan & Top Kategori: $label',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onSecondaryContainer,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

String _dashIfNull(double? value, String Function(double) format) =>
    value == null ? '-' : format(value);

/// Label pendek untuk sumbu-X chart Top Kategori — ambil kata pertama nama
/// kategori (mis. "Makan & Minum" -> "Makan"), dipangkas ke maksimal 10
/// karakter untuk kategori bernama satu kata panjang. Nama LENGKAP tetap
/// tampil di daftar legenda di bawah chart — cuma label di bawah bar yang
/// dipersingkat, sama seperti `shortLabel` pada mockup desain.
String _shortCategoryLabel(String name) {
  final String firstWord = name.trim().split(RegExp(r'\s+')).first;
  return firstWord.length > 10 ? firstWord.substring(0, 10) : firstWord;
}

/// Header section gaya headline-md (20px w600).
Widget _sectionHeader(BuildContext context, String text) => Text(
      text,
      style: Theme.of(context)
          .textTheme
          .titleLarge
          ?.copyWith(fontWeight: FontWeight.w600),
    );

/// Warna progress bar dinamis menurut persentase pemakaian:
/// <80% primary, 80-90% tertiary, >=90% error (roles M3, tanpa hex).
Color _progressColor(double percent, ColorScheme scheme) {
  if (percent >= 90) return scheme.error;
  if (percent >= 80) return scheme.tertiary;
  return scheme.primary;
}

class _SummaryCards extends ConsumerWidget {
  const _SummaryCards();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<PeriodTotals> state = ref.watch(periodTotalsProvider);
    final PeriodTotals? totals = state.valueOrNull;
    final double? rate = totals == null
        ? null
        : savingRate(
            income: totals.incomeMinor,
            expense: totals.expenseMinor,
          );

    // Nominal 0 tampil tanpa tanda +/- agar tidak muncul '-Rp0'.
    String signed(int amount, bool positive) => amount == 0
        ? 'Rp0'
        : '${positive ? '+' : '-'}${MoneyFormatter.format(amount.abs())}';

    final List<_SummaryData> tiles = <_SummaryData>[
      _SummaryData(
        label: 'Pemasukan',
        value: totals == null ? '-' : signed(totals.incomeMinor, true),
        color: FinanceColors.income,
      ),
      _SummaryData(
        label: 'Pengeluaran',
        value: totals == null ? '-' : signed(totals.expenseMinor, false),
        color: FinanceColors.expense,
      ),
      _SummaryData(
        label: 'Selisih',
        value:
            totals == null ? '-' : MoneyFormatter.format(totals.balanceMinor),
        color: (totals?.balanceMinor ?? 0) >= 0
            ? FinanceColors.income
            : FinanceColors.expense,
      ),
      _SummaryData(
        label: 'Saving Rate',
        value: _dashIfNull(rate, (double r) => '${r.toStringAsFixed(1)}%'),
        color: Theme.of(context).colorScheme.primary,
      ),
    ];

    // Bento 2x2 agar angka lega di layar sempit.
    return Column(
      children: <Widget>[
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(child: _SummaryTile(data: tiles[0])),
              const SizedBox(width: 12),
              Expanded(child: _SummaryTile(data: tiles[1])),
            ],
          ),
        ),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(child: _SummaryTile(data: tiles[2])),
              const SizedBox(width: 12),
              Expanded(child: _SummaryTile(data: tiles[3])),
            ],
          ),
        ),
      ],
    );
  }
}

class _SummaryData {
  const _SummaryData({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({required this.data});

  final _SummaryData data;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return AppCard.standard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            data.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 6),
          FittedBox(
            // Nilai berganti dengan cross-fade halus saat periode/filter
            // diubah — bukan lompatan angka mendadak.
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: kSharedMotionCurve,
              switchOutCurve: Curves.easeInCubic,
              child: Text(
                data.value,
                key: ValueKey<String>(data.value),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: data.color,
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthlyTrendCard extends ConsumerStatefulWidget {
  const _MonthlyTrendCard();

  @override
  ConsumerState<_MonthlyTrendCard> createState() => _MonthlyTrendCardState();
}

/// Bulan yang sedang di-tap pada grafik tren (null = tidak ada seleksi).
///
/// Tap ulang bulan yang sama membatalkan seleksi (toggle) — meniru
/// interaksi pada mockup desain ("Analisis Keuangan.dc.html"): dot bulan
/// terpilih tetap solid, dot lain meredup ke opacity 0.25.
class _MonthlyTrendCardState extends ConsumerState<_MonthlyTrendCard> {
  static const List<String> _monthLabels = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'Mei',
    'Jun',
    'Jul',
    'Agu',
    'Sep',
    'Okt',
    'Nov',
    'Des',
  ];

  int? _touchedMonth;

  FlDotPainter _dotPainter(Color color, int index) {
    final bool dim = _touchedMonth != null && _touchedMonth != index;
    return FlDotCirclePainter(
      radius: 3.5,
      color: color.withValues(alpha: dim ? 0.25 : 1),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<MonthSeriesPoint>> state =
        ref.watch(monthlySeriesProvider);
    final List<MonthSeriesPoint>? points = state.valueOrNull;

    // Tanpa pembungkus kartu: hidup di dalam grup analisis
    // ([AppCard.group]) — padding & bingkai milik grup.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _sectionHeader(context, 'Tren 12 Bulan'),
          const SizedBox(height: 4),
          Row(
            children: <Widget>[
              _legendDot(FinanceColors.income, 'Pemasukan'),
              const SizedBox(width: 16),
              _legendDot(FinanceColors.expense, 'Pengeluaran'),
            ],
          ),
          const SizedBox(height: 12),
          if (points == null)
            const Center(child: CircularProgressIndicator())
          else ...<Widget>[
            Builder(
              builder: (BuildContext context) {
                // Skala Y mengikuti rentang MIN-MAX data aktual (bukan dari
                // 0) — sama seperti mockup desain: garis jadi terlihat
                // dinamis naik-turun, bukan flat karena nilainya jutaan
                // rupiah dan hampir menyentuh puncak kalau dimulai dari 0.
                final List<int> allValues = <int>[
                  for (final MonthSeriesPoint p in points) ...<int>[
                    p.incomeMinor,
                    p.expenseMinor,
                  ],
                ];
                final int rawMin = allValues.reduce((a, b) => a < b ? a : b);
                final int rawMax = allValues.reduce((a, b) => a > b ? a : b);
                final double pad = (rawMax - rawMin) * 0.1;
                final double chartMinY =
                    pad == 0 ? 0 : (rawMin - pad).clamp(0, double.infinity);
                final double chartMaxY = pad == 0 ? rawMax * 1.1 : rawMax + pad;

                return SizedBox(
                  height: 180,
                  child: ChartReveal(
                    // Baru mulai menggambar SETELAH kartunya selesai memudar
                    // masuk, supaya gerakan "menggambar garis" benar-benar
                    // terlihat, bukan tenggelam oleh fade kartunya.
                    delay: const Duration(milliseconds: 100),
                    // Headroom horizontal: dot bulan pertama & terakhir ada
                    // TEPAT di tepi kotak chart (x = 0 dan x = 11), sedangkan
                    // fl_chart menggambar dot itu menonjol keluar kotaknya
                    // (clipData default = none) — tanpa padding ini separuh
                    // dot terpotong ClipRect reveal di tepi padding kartu.
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: LineChart(
                      LineChartData(
                        minY: chartMinY,
                        maxY: chartMaxY,
                        gridData: const FlGridData(show: false),
                        borderData: FlBorderData(show: false),
                        titlesData: FlTitlesData(
                          // fl_chart menampilkan left/top/right titles (angka
                          // minor unit mentah, mis. "8000000") secara DEFAULT
                          // kalau tidak dimatikan eksplisit — itu yang bikin
                          // labelnya bertabrakan dengan sumbu bulan di bawah.
                          // Chart ini cuma butuh label bulan, jadi tiga sisi
                          // lain dimatikan.
                          leftTitles: const AxisTitles(),
                          topTitles: const AxisTitles(),
                          rightTitles: const AxisTitles(),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              // interval 2 (bukan 1) — sama seperti mockup
                              // desain yang cuma menampilkan 6 label bulan
                              // (tiap 2 bulan), bukan 12 label penuh yang
                              // bikin sumbu-X sesak/bertabrakan.
                              interval: 2,
                              reservedSize: 24,
                              // Label bulan harus mengikuti bulan aktual titik
                              // (deret 12 bulan berakhir di bulan berjalan, jadi
                              // x=0 BUKAN Jan) — bukan index Jan-Des tetap.
                              getTitlesWidget: (double value, TitleMeta meta) =>
                                  SideTitleWidget(
                                axisSide: meta.axisSide,
                                child: Text(
                                  _monthLabels[points[value
                                              .toInt()
                                              .clamp(0, points.length - 1)]
                                          .monthStart
                                          .month -
                                      1],
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              ),
                            ),
                          ),
                        ),
                        lineTouchData: LineTouchData(
                          touchTooltipData: LineTouchTooltipData(
                            tooltipRoundedRadius: 10,
                            getTooltipColor: (_) =>
                                Theme.of(context).colorScheme.inverseSurface,
                            fitInsideHorizontally: true,
                            getTooltipItems: (List<LineBarSpot> touchedSpots) =>
                                touchedSpots.map((LineBarSpot spot) {
                              final int i =
                                  spot.x.toInt().clamp(0, points.length - 1);
                              final bool isIncome = spot.barIndex == 0;
                              return LineTooltipItem(
                                '${isIncome ? 'Masuk' : 'Keluar'}: '
                                '${MoneyFormatter.format(isIncome ? points[i].incomeMinor : points[i].expenseMinor)}',
                                TextStyle(
                                  color: isIncome
                                      ? FinanceColors.incomeOnDark
                                      : FinanceColors.expenseOnDark,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11,
                                ),
                              );
                            }).toList(),
                          ),
                          touchCallback: (FlTouchEvent event,
                              LineTouchResponse? response) {
                            if (event is! FlTapUpEvent) return;
                            final int? index =
                                response?.lineBarSpots?.isNotEmpty ?? false
                                    ? response!.lineBarSpots!.first.x.toInt()
                                    : null;
                            setState(() {
                              _touchedMonth =
                                  (index == null || _touchedMonth == index)
                                      ? null
                                      : index;
                            });
                          },
                        ),
                        lineBarsData: <LineChartBarData>[
                          LineChartBarData(
                            spots: <FlSpot>[
                              for (int i = 0; i < points.length; i++)
                                FlSpot(
                                  i.toDouble(),
                                  points[i].incomeMinor.toDouble(),
                                ),
                            ],
                            color: FinanceColors.income,
                            // Gaya "tumpul": garis melengkung halus (tanpa
                            // sudut lancip di titik bulan) + ujung/sambungan
                            // bulat. preventCurveOverShooting menjaga kurva
                            // tidak melewati nilai asli di titik datar.
                            isCurved: true,
                            curveSmoothness: 0.3,
                            preventCurveOverShooting: true,
                            isStrokeCapRound: true,
                            isStrokeJoinRound: true,
                            barWidth: 3,
                            dotData: FlDotData(
                              getDotPainter: (FlSpot spot, double percent,
                                      LineChartBarData bar, int index) =>
                                  _dotPainter(FinanceColors.income, index),
                            ),
                          ),
                          LineChartBarData(
                            spots: <FlSpot>[
                              for (int i = 0; i < points.length; i++)
                                FlSpot(
                                  i.toDouble(),
                                  points[i].expenseMinor.toDouble(),
                                ),
                            ],
                            color: FinanceColors.expense,
                            isCurved: true,
                            curveSmoothness: 0.3,
                            preventCurveOverShooting: true,
                            isStrokeCapRound: true,
                            isStrokeJoinRound: true,
                            barWidth: 3,
                            dotData: FlDotData(
                              getDotPainter: (FlSpot spot, double percent,
                                      LineChartBarData bar, int index) =>
                                  _dotPainter(FinanceColors.expense, index),
                            ),
                          ),
                        ],
                      ),
                      duration: kChartDataAnimationDuration,
                      curve: kSharedMotionCurve,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            // RichText — nominal masuk/keluar diwarnai hijau/merah alih-alih
            // satu warna abu-abu polos, konsisten dengan legend dot di atas.
            RichText(
              text: TextSpan(
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                children: <InlineSpan>[
                  const TextSpan(text: 'Bulan terakhir: '),
                  TextSpan(
                    text: MoneyFormatter.format(points.last.incomeMinor),
                    style: const TextStyle(
                      color: FinanceColors.income,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const TextSpan(text: ' masuk / '),
                  TextSpan(
                    text: MoneyFormatter.format(points.last.expenseMinor),
                    style: const TextStyle(
                      color: FinanceColors.expense,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const TextSpan(text: ' keluar'),
                ],
              ),
            ),
          ],
        ],
      );
  }

  static Widget _legendDot(Color color, String label) => Row(
        children: <Widget>[
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(label),
        ],
      );
}

class _TopCategoriesCard extends ConsumerStatefulWidget {
  const _TopCategoriesCard();

  @override
  ConsumerState<_TopCategoriesCard> createState() => _TopCategoriesCardState();
}

/// Kategori yang sedang di-tap (bar ATAU baris legenda, keduanya saling
/// terhubung) — tap ulang membatalkan seleksi. Meniru interaksi mockup:
/// bar/baris terpilih membesar & solid, sisanya meredup ke opacity 0.3.
class _TopCategoriesCardState extends ConsumerState<_TopCategoriesCard> {
  int? _touchedCategory;

  void _toggle(int index) {
    setState(() {
      _touchedCategory = _touchedCategory == index ? null : index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<CategorySlice>> state =
        ref.watch(categorySlicesProvider(TransactionType.expense));
    final List<CategorySlice>? slices = state.valueOrNull;

    // Tanpa pembungkus kartu: hidup di dalam grup analisis
    // ([AppCard.group]) — padding & bingkai milik grup.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _sectionHeader(context, 'Top Kategori Pengeluaran'),
          const SizedBox(height: 12),
          if (slices == null)
            const Center(child: CircularProgressIndicator())
          else if (slices.isEmpty)
            Text(
              'Belum ada data pada periode ini.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            )
          else ...<Widget>[
            SizedBox(
              height: 160,
              child: ChartReveal(
                // Seperti chart tren: menggambar setelah kartu memudar masuk.
                delay: const Duration(milliseconds: 100),
                child: BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    barTouchData: BarTouchData(
                      touchTooltipData: BarTouchTooltipData(
                        getTooltipColor: (_) =>
                            Theme.of(context).colorScheme.inverseSurface,
                        getTooltipItem: (BarChartGroupData group,
                            int groupIndex, BarChartRodData rod, int rodIndex) {
                          final CategorySlice slice = slices[groupIndex];
                          return BarTooltipItem(
                            '${slice.category.name}\n'
                            '${MoneyFormatter.format(slice.totalMinor)}',
                            TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onInverseSurface,
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
                            ),
                          );
                        },
                      ),
                      touchCallback:
                          (FlTouchEvent event, BarTouchResponse? response) {
                        if (event is! FlTapUpEvent) return;
                        final int? index = response?.spot?.touchedBarGroupIndex;
                        if (index != null) _toggle(index);
                      },
                    ),
                    gridData: const FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                    titlesData: FlTitlesData(
                      // Sama seperti chart Tren 12 Bulan — left/top/right
                      // titles default fl_chart ON (angka minor unit mentah)
                      // dan bertabrakan dengan label kategori di bawah kalau
                      // tidak dimatikan eksplisit.
                      leftTitles: const AxisTitles(),
                      topTitles: const AxisTitles(),
                      rightTitles: const AxisTitles(),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 32,
                          getTitlesWidget: (double value, TitleMeta meta) =>
                              SideTitleWidget(
                            axisSide: meta.axisSide,
                            child: Text(
                              // Diklem ke rentang valid seperti label chart
                              // tren bulanan — fl_chart bisa meminta posisi
                              // sedikit di luar jumlah bar yang benar-benar
                              // digambar (mis. saat kategori < 5), dan tanpa
                              // clamp ini melempar RangeError.
                              //
                              // Label DIPERSINGKAT (bukan nama kategori penuh)
                              // — sama seperti mockup desain yang pakai
                              // `shortLabel` khusus di bawah bar (nama penuh
                              // tetap tampil di daftar legenda di bawahnya).
                              _shortCategoryLabel(
                                slices[value
                                        .toInt()
                                        .clamp(0, slices.length - 1)]
                                    .category
                                    .name,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ),
                        ),
                      ),
                    ),
                    barGroups: <BarChartGroupData>[
                      for (int i = 0; i < slices.length && i < 5; i++)
                        BarChartGroupData(
                          x: i,
                          barRods: <BarChartRodData>[
                            BarChartRodData(
                              toY: slices[i].totalMinor.toDouble(),
                              color: (slices[i].category.colorValue != null
                                      ? Color(slices[i].category.colorValue!)
                                      : Theme.of(context).colorScheme.primary)
                                  .withValues(
                                alpha: _touchedCategory == null ||
                                        _touchedCategory == i
                                    ? 1
                                    : 0.3,
                              ),
                              width: _touchedCategory == i ? 22 : 18,
                              // Gaya "tumpul": keempat sudut bar membulat
                              // (dulu hanya sudut atas, radius 4).
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ],
                        ),
                    ],
                  ),
                  duration: kChartDataAnimationDuration,
                  curve: kSharedMotionCurve,
                ),
              ),
            ),
            const SizedBox(height: 8),
            for (int i = 0; i < slices.take(5).length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _toggle(i),
                  child: Opacity(
                    opacity: _touchedCategory == null || _touchedCategory == i
                        ? 1
                        : 0.3,
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            slices[i].category.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        Text(
                          MoneyFormatter.format(slices[i].totalMinor),
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ],
      );
  }
}

class _MonthComparisonCard extends ConsumerStatefulWidget {
  const _MonthComparisonCard();

  @override
  ConsumerState<_MonthComparisonCard> createState() =>
      _MonthComparisonCardState();
}

/// Tap kartu -> buka/tutup rincian nominal bulan ini vs bulan lalu (bukan
/// cuma selisihnya). Teks selisih & persen diwarnai hijau/merah — SEBELUMNYA
/// selalu abu-abu netral meski ikon trending sudah hijau/merah, jadi kurang
/// konsisten & kurang "menonjol" secara visual.
class _MonthComparisonCardState extends ConsumerState<_MonthComparisonCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final PeriodComparison? comparison = ref.watch(monthOverMonthProvider);
    final double? pct = comparison?.percentChange;
    final bool up = (comparison?.deltaMinor ?? 0) >= 0;
    final Color trendColor = up ? FinanceColors.income : FinanceColors.expense;

    // Tanpa pembungkus kartu: hidup di dalam grup analisis. InkWell
    // dipertahankan (toggle expand), padding horizontal dibuang karena
    // grup sudah memberi 16.
    return InkWell(
      onTap: comparison == null
          ? null
          : () => setState(() => _expanded = !_expanded),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    up
                        ? Icons.trending_up_outlined
                        : Icons.trending_down_outlined,
                    color: trendColor,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text('Pengeluaran Bulan Ini vs Lalu'),
                        const SizedBox(height: 2),
                        comparison == null
                            ? const Text('-')
                            : Text(
                                '${MoneyFormatter.format(comparison.deltaMinor)} '
                                '(${pct == null ? '-' : '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(1)}%'})',
                                style: TextStyle(
                                  color: trendColor,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ],
                    ),
                  ),
                  if (comparison != null)
                    // Chevron berputar halus saat kartu dibuka/tutup.
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        Icons.expand_more,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: kSharedMotionCurve,
                alignment: Alignment.topCenter,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (_expanded && comparison != null) ...<Widget>[
                      const SizedBox(height: 10),
                      Divider(
                        height: 1,
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: <Widget>[
                          _MiniStat(
                            label: 'Bulan ini',
                            value:
                                MoneyFormatter.format(comparison.currentMinor),
                            color: FinanceColors.expense,
                          ),
                          _MiniStat(
                            label: 'Bulan lalu',
                            value:
                                MoneyFormatter.format(comparison.previousMinor),
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(fontWeight: FontWeight.w700, color: color),
        ),
      ],
    );
  }
}

class _ForecastCard extends ConsumerStatefulWidget {
  const _ForecastCard();

  @override
  ConsumerState<_ForecastCard> createState() => _ForecastCardState();
}

/// Tap kartu -> buka/tutup rincian net 3 bulan terakhir yang jadi dasar
/// rata-rata bergerak. Nominal proyeksi diwarnai hijau/merah menurut
/// tandanya — SEBELUMNYA selalu warna teks netral meski nilainya bisa
/// negatif (proyeksi defisit), jadi tidak ada isyarat visual sama sekali.
class _ForecastCardState extends ConsumerState<_ForecastCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final double? forecast = ref.watch(netForecastProvider);
    final List<MonthSeriesPoint>? points =
        ref.watch(monthlySeriesProvider).valueOrNull;
    final Color forecastColor = forecast == null
        ? Theme.of(context).colorScheme.onSurface
        : forecast >= 0
            ? FinanceColors.income
            : FinanceColors.expense;
    final List<MonthSeriesPoint> last3 = points == null
        ? const <MonthSeriesPoint>[]
        : points.reversed.take(3).toList().reversed.toList();

    // Tanpa pembungkus kartu: hidup di dalam grup analisis. InkWell
    // dipertahankan (toggle expand), padding horizontal dibuang karena
    // grup sudah memberi 16.
    return InkWell(
      onTap:
          last3.isEmpty ? null : () => setState(() => _expanded = !_expanded),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Icon(Icons.query_stats_outlined),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text('Proyeksi Net Bulan Depan'),
                        SizedBox(height: 2),
                        Text('Rata-rata bergerak 3 bulan terakhir'),
                      ],
                    ),
                  ),
                  Text(
                    _dashIfNull(
                      forecast,
                      (double v) => MoneyFormatter.formatCompact(v.round()),
                    ),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: forecastColor,
                        ),
                  ),
                  if (last3.isNotEmpty)
                    // Chevron berputar halus saat kartu dibuka/tutup.
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        Icons.expand_more,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: kSharedMotionCurve,
                alignment: Alignment.topCenter,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (_expanded && last3.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 10),
                      Divider(
                        height: 1,
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: <Widget>[
                          for (final MonthSeriesPoint p in last3)
                            _MiniStat(
                              label: _MonthlyTrendCardState
                                  ._monthLabels[p.monthStart.month - 1],
                              value: MoneyFormatter.formatCompact(p.netMinor),
                              color: p.netMinor >= 0
                                  ? FinanceColors.income
                                  : FinanceColors.expense,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );
  }
}

class _HealthScoreCard extends ConsumerStatefulWidget {
  const _HealthScoreCard();

  @override
  ConsumerState<_HealthScoreCard> createState() => _HealthScoreCardState();
}

/// Baris skor yang sedang di-tap — tap ulang membatalkan seleksi. Meniru
/// interaksi mockup: baris terpilih tetap solid, sisanya meredup ke 0.3.
class _HealthScoreCardState extends ConsumerState<_HealthScoreCard> {
  static const List<(String, double)> _componentRows = <(String, double)>[
    ('Saving Rate', 20),
    ('Kontrol Budget', 20),
    ('Stabilitas Pengeluaran', 20),
    ('Progress Tujuan', 20),
    ('Rasio Utang', 20),
  ];

  int? _touchedRow;

  @override
  Widget build(BuildContext context) {
    final FinancialHealthScore score = ref.watch(healthScoreProvider);
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final List<double> points = <double>[
      score.savingRatePoints,
      score.budgetControlPoints,
      score.expenseStabilityPoints,
      score.goalProgressPoints,
      score.debtRatioPoints,
    ];

    // Tanpa pembungkus kartu: hidup di dalam grup analisis
    // ([AppCard.group]) — padding & bingkai milik grup.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _sectionHeader(context, 'Skor Kesehatan Finansial'),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                score.total.toStringAsFixed(0),
                key: const Key('analytics_health_score'),
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: scheme.primary,
                    ),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '/100',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Progress bar skor total (dinamis menurut persen skor).
          AnimatedProgressBar(
            value: (score.total / 100).clamp(0.0, 1.0),
            backgroundColor: scheme.surfaceContainerHighest,
            color: _progressColor(score.total, scheme),
          ),
          const SizedBox(height: 12),
          for (int i = 0; i < _componentRows.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => setState(
                  () => _touchedRow = _touchedRow == i ? null : i,
                ),
                child: Opacity(
                  opacity: _touchedRow == null || _touchedRow == i ? 1 : 0.3,
                  child: Column(
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              _componentRows[i].$1,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                          Text(
                            '${points[i].toStringAsFixed(0)} / '
                            '${_componentRows[i].$2.toStringAsFixed(0)}',
                            // Diwarnai sesuai kualitas komponen (bukan warna
                            // teks netral) — hijau/kuning/merah, cermin dari
                            // warna progress bar-nya sendiri di bawah ini.
                            // Skala kebalikan dari _progressColor (dipakai
                            // untuk PEMAKAIAN budget, makin tinggi makin
                            // buruk): di sini makin TINGGI poin makin BAIK.
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: _progressColor(
                                    100 -
                                        (points[i] /
                                            _componentRows[i].$2 *
                                            100),
                                    scheme,
                                  ),
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      AnimatedProgressBar(
                        value:
                            (points[i] / _componentRows[i].$2).clamp(0.0, 1.0),
                        minHeight: 4,
                        backgroundColor: scheme.surfaceContainerHighest,
                        color: _progressColor(
                          points[i] / _componentRows[i].$2 * 100,
                          scheme,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 4),
          Text(
            'Komponen tanpa data bernilai netral (10).',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ],
      );
  }
}
