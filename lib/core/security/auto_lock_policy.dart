/// Mesin status auto-lock — PURE, jam injectable (`DateTime Function()`)
/// sehingga skenario batas waktu dapat diuji dengan clock palsu (BP-06).
///
/// Aturan:
/// - timeoutMinutes NULL  = auto-lock NONAKTIF (tidak pernah kunci).
/// - timeoutMinutes == 0    = langsung kunci segera setelah background.
/// - default                = 2 menit.
/// - `shouldLock` benar bila sudah terkunci ATAU jeda background >=
///   timeout. Event: appBackgrounded / appResumed / unlockSuccess /
///   setTimeoutMinutes.
library;

class AutoLockPolicy {
  AutoLockPolicy({
    DateTime Function()? clock,
    int? timeoutMinutes = kDefaultAutoLockMinutes,
  }) : _clock = clock ?? DateTime.now,
       _timeoutMinutes = timeoutMinutes;

  /// Default 2 menit sesuai spesifikasi produk.
  static const int kDefaultAutoLockMinutes = 2;

  final DateTime Function() _clock;

  int? _timeoutMinutes;
  DateTime? _backgroundedAt;
  bool _locked = false;

  /// Menit timeout; NULL = nonaktif, 0 = langsung.
  int? get timeoutMinutes => _timeoutMinutes;
  DateTime? get backgroundedAt => _backgroundedAt;
  bool get isLocked => _locked;

  /// Ubah timeout (bisa dipanggil kapan pun, termasuk saat background).
  void setTimeoutMinutes(int? minutes) {
    if (minutes != null && minutes < 0) {
      throw ArgumentError.value(minutes, 'minutes', 'Tidak boleh negatif');
    }
    _timeoutMinutes = minutes;
  }

  /// App masuk background — catat waktu mulai hanya bila belum terkunci.
  void appBackgrounded() {
    if (_locked) return;
    _backgroundedAt = _clock();
  }

  /// Apakah gerbang harus menampilkan lock screen SEKARANG?
  bool get shouldLock {
    if (_locked) return true;
    final DateTime? bg = _backgroundedAt;
    final int? minutes = _timeoutMinutes;
    if (bg == null || minutes == null) return false;
    // Non-const per BP-06; Duration konstruksi biasa.
    final DateTime deadline = bg.add(Duration(minutes: minutes));
    return !_clock().isBefore(deadline);
  }

  /// Sisa detik menuju lock (0 bila sudah waktunya / tidak relevant).
  int secondsUntilLock() {
    if (_locked) return 0;
    final DateTime? bg = _backgroundedAt;
    final int? minutes = _timeoutMinutes;
    if (bg == null || minutes == null) return -1;
    final DateTime deadline = bg.add(Duration(minutes: minutes));
    final int remaining = deadline.difference(_clock()).inSeconds;
    return remaining < 0 ? 0 : remaining;
  }

  /// App resume: evaluasi keputusan lock, lalu bersihkan marker
  /// background. Setelah method ini, [shouldLock] mencerminkan hasil
  /// akhir (true bila terkunci).
  void appResumed() {
    if (!_locked && shouldLock) {
      _locked = true;
    }
    _backgroundedAt = null;
  }

  /// Paksa kunci segera (mis. aksi pengguna "Kunci sekarang").
  void lockNow() => _locked = true;

  /// PIN benar dimasukkan — buka kunci & reset state background.
  void unlockSuccess() {
    _locked = false;
    _backgroundedAt = null;
  }
}
