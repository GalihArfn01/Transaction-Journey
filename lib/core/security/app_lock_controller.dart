import 'package:flutter/widgets.dart';

import 'auto_lock_policy.dart';

/// Controller gerbang auto-lock untuk di-pasang di AppShell (wiring oleh A).
///
/// Menggabungkan [AutoLockPolicy] (mesin waktu murni) dengan status PIN
/// (via loader `Future<bool> Function()` — biasanya
/// `securityRepository.hasPin`) menjadi state tunggal `{isLocked, hasPin}`.
///
/// Aturan:
/// - SEMUA keputusan logika ada DI SINI sehingga [AppLockGate] tinggal
///   merender hasilnya — test cukup memanggil method tanpa pump penuh.
/// - `notifyListeners` dipanggil TEPAT SEKALI per transisi state
///   (nilai yang sama tidak diberi tahu ulang).
/// - Loader PIN disuntik sebagai fungsi (bukan repository) agar layer
///   core tidak bergantung pada layer data.
class AppLockController extends ChangeNotifier {
  AppLockController({
    required AutoLockPolicy autoLockPolicy,
    required Future<bool> Function() loadHasPin,
  }) : _autoLockPolicy = autoLockPolicy,
       _hasPinLoader = loadHasPin;

  final AutoLockPolicy _autoLockPolicy;
  final Future<bool> Function() _hasPinLoader;

  bool _isLocked = false;
  bool _hasPin = false;

  /// Policy dasar — diekspos agar wiring (A) bisa menyinkronkan timeout
  /// dari settings (`autoLockPolicy.setTimeoutMinutes(...)`).
  AutoLockPolicy get autoLockPolicy => _autoLockPolicy;

  /// True bila gerbang harus menutup (keputusan policy mentah).
  /// Gerbang tetap menampilkan child bila [hasPin] false.
  bool get isLocked => _isLocked;

  /// Status PIN terakhir yang dimuat via [loadHasPin].
  bool get hasPin => _hasPin;

  /// Muat/refresh status PIN dari loader. Notify hanya bila nilainya
  /// benar-benar berubah.
  Future<void> loadHasPin() async {
    final bool hasPin = await _hasPinLoader();
    if (_hasPin == hasPin) return;
    _hasPin = hasPin;
    notifyListeners();
  }

  /// Paksa terkunci SEKARANG kalau PIN terpasang — dipanggil TEPAT SEKALI
  /// oleh pemanggil di cold start (lihat `app.dart`), BUKAN oleh
  /// [loadHasPin] yang juga dipakai untuk me-refresh status PIN setelah
  /// pengguna mengubahnya di halaman Keamanan (memaksa lock di situ akan
  /// mengunci pengguna sendiri tepat setelah memasang PIN baru).
  ///
  /// PENTING: `_isLocked`/`_backgroundedAt` di [AutoLockPolicy] murni
  /// in-memory — begitu proses aplikasi benar-benar dimatikan (di-swipe
  /// dari recent apps, di-force-stop, atau dibunuh sistem karena low
  /// memory), SEMUA state itu hilang total dan controller yang baru
  /// dibuat mulai dari `_isLocked = false` lagi. Tanpa method ini, buka
  /// ulang aplikasi setelah proses mati akan langsung ke Dashboard tanpa
  /// diminta PIN sama sekali — padahal dari sudut pandang keamanan,
  /// proses baru = sesi baru = HARUS selalu diverifikasi ulang dulu,
  /// terlepas dari sudah berapa lama timeout auto-lock berjalan (yang
  /// justru tidak relevan lagi karena tidak ada "durasi di background"
  /// yang bisa diukur dari proses yang sudah tidak ada).
  void lockOnColdStartIfHasPin() {
    if (!_hasPin) return;
    _autoLockPolicy.lockNow();
    if (_isLocked) return;
    _isLocked = true;
    notifyListeners();
  }

  /// Penerima event siklus hidup aplikasi (dari WidgetsBindingObserver):
  /// - paused  -> policy.appBackgrounded (catat waktu masuk background)
  /// - resumed -> evaluasi keputusan lock (lihat [checkOnResume])
  /// - state lain (inactive/detached/hidden) diabaikan sesuai spesifikasi.
  void didChangeLifecycle(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        _autoLockPolicy.appBackgrounded();
      case AppLifecycleState.resumed:
        checkOnResume();
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }

  /// Evaluasi apakah LockScreen harus tampil SAAT INI (dipanggil saat
  /// resume). Return true bila harus terkunci; state + notify hanya
  /// berubah bila hasilnya berbeda dari sebelumnya.
  bool checkOnResume() {
    _autoLockPolicy.appResumed();
    final bool locked = _autoLockPolicy.shouldLock;
    if (_isLocked == locked) return locked;
    _isLocked = locked;
    notifyListeners();
    return locked;
  }

  /// PIN benar dimasukkan — buka kunci. Idempoten: memanggil saat sudah
  /// terbuka tidak memberi tahu listener.
  void unlock() {
    _autoLockPolicy.unlockSuccess();
    if (!_isLocked) return;
    _isLocked = false;
    notifyListeners();
  }
}

/// Widget pembungkus gerbang kunci: bila `controller.isLocked` DAN
/// `controller.hasPin` -> render [lockScreenBuilder] MENUTUPI [child]
/// (bukan MENGGANTIKAN-nya) lewat [Stack]; selain itu [lockScreenBuilder]
/// tidak dirender sama sekali.
///
/// PENTING (perbaikan celah keamanan): [child] harus dipasang di ATAS
/// `Navigator` aplikasi (mis. via `MaterialApp.builder`), bukan di dalam
/// salah satu halaman shell — supaya lock screen menutupi SEMUA layar
/// (termasuk yang di-push, seperti form tambah transaksi), bukan cuma
/// 4 tab utama. Sebelum perbaikan ini, gate hanya membungkus body
/// `AppShell`; halaman yang di-push lewat `Navigator.push` ditumpuk di
/// ATAS AppShell pada Navigator yang sama sehingga tidak pernah tertutup
/// lock screen saat app di-resume dari background.
///
/// [child] SENGAJA tetap dipertahankan di tree (bukan dilepas) saat
/// terkunci — kalau gate mengganti child dengan lockScreenBuilder
/// (bukan menumpuknya), seluruh Navigator di bawahnya ikut di-dispose
/// setiap kali lock/unlock, menghapus back-stack & state halaman yang
/// sedang dibuka pengguna.
///
/// Widget ini SENGAJA tanpa logika sendiri — rebuild dipicu listener ke
/// controller, keputusan ada di [AppLockController].
class AppLockGate extends StatefulWidget {
  const AppLockGate({
    required this.controller,
    required this.child,
    required this.lockScreenBuilder,
    super.key,
  });

  final AppLockController controller;
  final Widget child;
  final WidgetBuilder lockScreenBuilder;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(AppLockGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
    }
  }

  void _handleControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool showLock =
        widget.controller.isLocked && widget.controller.hasPin;
    return Stack(
      children: <Widget>[
        // Selalu terpasang (bukan kondisional) — Navigator/state di
        // bawahnya tidak boleh pernah di-dispose akibat lock/unlock.
        widget.child,
        if (showLock)
          Positioned.fill(
            // `Material` + latar tidak transparan: menutup total layar
            // di bawahnya secara visual DAN menyerap semua sentuhan
            // (hit-test berhenti di widget teratas yang opaque),
            // sehingga halaman di bawah benar-benar tidak bisa
            // dioperasikan selama terkunci.
            child: widget.lockScreenBuilder(context),
          ),
      ],
    );
  }
}
