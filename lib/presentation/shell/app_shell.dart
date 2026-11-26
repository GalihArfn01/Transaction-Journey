import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_theme.dart' show AppGradients, AppShadows;
import '../analytics/analytics_page.dart';
import '../dashboard/dashboard_page.dart';
import '../settings/settings_page.dart';
import '../shared/widgets/animations.dart';
import '../transactions/add_edit_transaction_page.dart';
import '../transactions/transactions_page.dart';
import '../shared/transitions/form_slide_up_transitions.dart';

/// Shell utama: NavigationBar M3 dengan 4 tujuan + FAB tambah transaksi
/// DOCKED DI TENGAH agar mudah dijangkau satu jempol.
///
/// Memakai `NavigationBar` bawaan M3 (bukan BottomAppBar + InkWell
/// tulisan tangan) supaya state terpilih tersuarakan ke screen reader,
/// ripple/indikator mengikuti `navigationBarTheme` di `app_theme.dart`,
/// dan perilaku sentuh konsisten dengan seluruh aplikasi.
///
/// Celah tengah untuk FAB dibuat dengan slot kosong (`SizedBox.shrink`)
/// di tengah daftar `destinations` — `destinations` bertipe `List<Widget>`
/// dan InkWell tap hanya ada DI DALAM `NavigationDestination`, jadi slot
/// kosong tidak bisa ditekan dan tidak ikut traversal screen reader.
///
/// TRANSISI DUA LAPIS saat berpindah tab (permintaan pengguna: "hanya isi
/// halamannya yang bertransisi, latar putihnya tetap di posisi"):
///
/// 1. **Latar** dipasang SEKALI di sini — `ColoredBox` di `Scaffold.body`,
///    di LUAR pohon yang dianimasikan — dan tiap halaman tab dibuat
///    transparan (`Scaffold(backgroundColor: Colors.transparent)`). Jadi
///    lapisan latar itu tidak pernah ikut memudar maupun bergeser.
/// 2. **Isi halaman** di-cross-fade di posisi yang sama (`_TabLayer` +
///    [FadeTransition]): halaman baru muncul sambil halaman lama hilang.
///    Sengaja TANPA geser vertikal — menggeser seluruh halaman membuat
///    pita latar muncul di atas header (header biru "turun" lalu naik
///    lagi), persis yang ingin dihindari.
///
/// CATATAN: gerbang auto-lock (`AppLockGate`) TIDAK lagi dipasang di
/// sini — ia dipindah ke `TransactionJourneyApp` (lewat
/// `MaterialApp.builder`) supaya menutupi SELURUH Navigator, termasuk
/// halaman yang di-push dari shell ini (mis. `AddEditTransactionPage`),
/// bukan cuma 4 tab di bawah. Lihat `app/app.dart` dan dokumentasi
/// `AppLockGate` di `core/security/app_lock_controller.dart`.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell>
    with SingleTickerProviderStateMixin {
  /// Index HALAMAN aktif (0-3), bukan index destinasi bar.
  int _index = 0;

  /// Halaman yang sedang MEMUDAR KELUAR (`null` = tidak ada transisi
  /// berjalan). Hanya satu halaman lama yang pernah ditampilkan sekaligus,
  /// jadi satu slot sudah cukup.
  int? _outgoingIndex;

  /// Durasi transisi ganti tab (dipangkas otomatis saat intensitas animasi
  /// "ringan" — lihat [didChangeDependencies]).
  static const Duration _tabTransitionDuration = Duration(milliseconds: 200);

  /// Animasi cross-fade ganti tab — HANYA konten halaman, latar statis
  /// disediakan `Scaffold` shell di luar pohon ini (lihat [build]).
  late final AnimationController _tabTransition = AnimationController(
    vsync: this,
    duration: _tabTransitionDuration,
    value: 1,
  )..addStatusListener(_onTabTransitionStatus);

  /// Halaman yang sedang masuk: 0 -> 1.
  late final Animation<double> _tabFadeIn = CurvedAnimation(
    parent: _tabTransition,
    curve: kSharedMotionCurve,
  );

  /// Halaman yang sedang keluar: 1 -> 0 (kebalikan [_tabFadeIn]).
  late final Animation<double> _tabFadeOut = ReverseAnimation(_tabFadeIn);

  /// Pemetaan index destinasi BAR -> index halaman. Slot 2 adalah celah
  /// FAB (tidak bisa dipilih). Halaman: 0 Dashboard, 1 Transaksi,
  /// 2 Analisis, 3 Pengaturan.
  static const List<int?> _barToPage = <int?>[0, 1, null, 2, 3];

  /// Index destinasi bar untuk halaman aktif (meng-skip celah FAB).
  int get _selectedDestination => _index < 2 ? _index : _index + 1;

  static const List<Widget> _pages = <Widget>[
    DashboardPage(),
    TransactionsPage(),
    AnalyticsPage(),
    SettingsPage(),
  ];

  /// Epoch reveal PER HALAMAN: dinaikkan hanya untuk halaman yang baru
  /// dibuka (lihat [RevealScope]) supaya kartu & chart di halaman itu
  /// diputar ulang animasinya — halaman tab sengaja tetap hidup di dalam
  /// [Stack] (state-nya terjaga), jadi tanpa ini halaman yang pernah
  /// dibuka tidak pernah beranimasi lagi. Halaman lain dibiarkan (tidak
  /// beranimasi sia-sia di belakang tab yang sedang tidak terlihat).
  final List<int> _pageEpochs = <int>[0, 0, 0, 0];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // "Ringan" memangkas separuh durasi. "Mati"/reduce-motion sistem tidak
    // dianimasikan sama sekali — lihat [_onDestinationSelected].
    _tabTransition.duration = motionDuration(context, _tabTransitionDuration);
  }

  @override
  void dispose() {
    _tabTransition.dispose();
    super.dispose();
  }

  /// Transisi selesai: halaman lama berhenti digambar. State-nya TIDAK
  /// hilang — widgetnya tetap hidup di dalam [Stack], hanya di-`Offstage`.
  void _onTabTransitionStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || _outgoingIndex == null) return;
    setState(() => _outgoingIndex = null);
  }

  Future<void> _onAddPressed() async {
    await Navigator.of(context).push<void>(
      formSlideUpRoute<void>(builder: (_) => const AddEditTransactionPage()),
    );
  }

  void _onDestinationSelected(int barIndex) {
    final int? page = _barToPage[barIndex];
    if (page == null || page == _index) return;
    // Umpan balik haptic ringan saat ganti tab — tab terasa "klik".
    HapticFeedback.selectionClick();
    final bool animate = !prefersReducedMotion(context);
    setState(() {
      _outgoingIndex = animate ? _index : null;
      _index = page;
      _pageEpochs[page] = _pageEpochs[page] + 1;
    });
    if (animate) {
      _tabTransition.forward(from: 0);
    } else {
      _tabTransition.value = 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // LAPISAN 1 — LATAR STATIS. Berada DI LUAR [Stack] yang dianimasikan,
      // jadi tidak pernah ikut fade/geser saat ganti tab. Halaman tab
      // sendiri transparan (`backgroundColor: Colors.transparent`), jadi
      // yang terlihat di belakang kontennya adalah lapisan ini.
      body: ColoredBox(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            // LAPISAN 1b — PITA HEADER STATIS. Keempat tab memakai
            // `GradientAppBar` yang identik (gradient & tinggi sama, di
            // posisi yang sama), tapi AppBar itu ikut memudar bersama
            // halamannya. Tanpa pita ini, di tengah cross-fade kedua
            // halaman sama-sama setengah transparan sehingga latar PUTIH
            // tembus di area header -> header biru "berkedip putih" setiap
            // ganti tab (terlihat jelas di rekaman layar). Dengan pita ini
            // yang tembus justru biru yang sama, jadi header tampak diam
            // dan hanya teks judulnya yang bertukar.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: MediaQuery.paddingOf(context).top + kToolbarHeight,
              child: const DecoratedBox(
                decoration: BoxDecoration(gradient: AppGradients.hero),
              ),
            ),
            // LAPISAN 2 — ISI HALAMAN. Semua tab tetap hidup di sini
            // (posisi gulir & isian tidak hilang); hanya yang sedang
            // tampil/keluar yang digambar (lihat [_TabLayer]).
            for (int i = 0; i < _pages.length; i++)
              _TabLayer(
                visible: i == _index || i == _outgoingIndex,
                interactive: i == _index,
                opacity: i == _index ? _tabFadeIn : _tabFadeOut,
                child: RevealScope(epoch: _pageEpochs[i], child: _pages[i]),
              ),
          ],
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: AnimatedEntrance(
        // FAB "pop" masuk (scale) agar tidak muncul mendadak.
        slideOffset: 0,
        scaleFrom: 0.85,
        delay: const Duration(milliseconds: 140),
        child: FloatingActionButton(
          onPressed: _onAddPressed,
          tooltip: 'Tambah transaksi',
          shape: const CircleBorder(),
          child: const Icon(Icons.add),
        ),
      ),
      // NavigationBar M3 bawaan: state terpilih tersuarakan ke screen
      // reader, indikator/ripple dari navigationBarTheme (app_theme.dart).
      // FAB centerDocked melayang di atas SLOT KOSONG di tengah bar
      // (lihat [_barToPage]) — celah dibuat manual karena NavigationBar
      // tidak punya konsep notch seperti BottomAppBar.
      bottomNavigationBar: _FloatingNavBar(
        child: NavigationBar(
          selectedIndex: _selectedDestination,
          height: 64,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          onDestinationSelected: _onDestinationSelected,
          // Latar & elevasi dipegang kapsul [_FloatingNavBar]; bar sendiri
          // transparan supaya sudut membulat kapsul terlihat bersih.
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          destinations: const <Widget>[
            NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard),
              label: 'Dashboard',
              tooltip: 'Dashboard',
            ),
            NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long),
              label: 'Transaksi',
              tooltip: 'Transaksi',
            ),
            // Slot tengah KOSONG: celah untuk FAB centerDocked. Widget
            // kosong tidak punya InkWell -> tidak bisa ditekan.
            SizedBox.shrink(),
            NavigationDestination(
              icon: Icon(Icons.insights_outlined),
              selectedIcon: Icon(Icons.insights),
              label: 'Analisis',
              tooltip: 'Analisis',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Pengaturan',
              tooltip: 'Pengaturan',
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom menu berbentuk KAPSUL MELAYANG: sudut membulat penuh, margin
/// dari tepi layar, latar putih + bayangan lembut yang sama dengan kartu
/// ([AppShadows.card]) — menggantikan bar datar selebar layar.
///
/// Tidak ada margin ATAS: FAB `centerDocked` menempel pada tepi atas
/// widget `bottomNavigationBar`, jadi tepi atas kapsul = garis tambat FAB
/// (FAB tetap tepat di tengah, setengah menjorok di atas kapsul).
///
/// Inset sistem (gesture bar) ditangani SEKALI di sini lewat `SafeArea`,
/// lalu dihapus dari `MediaQuery` untuk `NavigationBar` di dalamnya —
/// kalau tidak, bar menambah tinggi sendiri untuk inset itu dan kapsul
/// jadi terlalu tinggi.
class _FloatingNavBar extends StatelessWidget {
  const _FloatingNavBar({required this.child});

  final Widget child;

  static const double _radius = 28;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final BorderRadius radius = BorderRadius.circular(_radius);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLowest,
            borderRadius: radius,
            boxShadow: AppShadows.card(scheme),
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: MediaQuery.removePadding(
              context: context,
              removeBottom: true,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Satu tab di dalam [Stack] shell.
///
/// Tab yang tidak sedang tampil di-`Offstage` — tidak digambar, tidak bisa
/// disentuh, tidak ikut dibaca screen reader, dan dilewati finder test
/// (perilaku yang sama dengan `IndexedStack` yang dipakai sebelumnya) —
/// TAPI widgetnya tetap hidup di pohon supaya state tab (posisi gulir,
/// isian form) tidak hilang.
///
/// Tab yang sedang keluar (memudar) tetap digambar tapi dibuat
/// `IgnorePointer` agar tap selalu jatuh ke halaman yang sedang aktif,
/// berapa pun urutan tumpukannya di dalam [Stack].
class _TabLayer extends StatelessWidget {
  const _TabLayer({
    required this.visible,
    required this.interactive,
    required this.opacity,
    required this.child,
  });

  /// `true` kalau tab ini harus digambar (aktif atau sedang memudar keluar).
  final bool visible;

  /// `true` hanya untuk tab yang sedang aktif (menerima sentuhan).
  final bool interactive;

  final Animation<double> opacity;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!visible) {
      // `offstage` default = true.
      return Offstage(child: child);
    }
    return IgnorePointer(
      ignoring: !interactive,
      child: FadeTransition(opacity: opacity, child: child),
    );
  }
}
