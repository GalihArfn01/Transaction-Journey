import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import '../../core/security/auto_lock_policy.dart';
import '../../core/security/pin_hasher.dart';
import '../datasource/app_database.dart';

/// Kunci penyimpanan milik modul keamanan.
///
/// `pin_salt`/`pin_hash` KINI DISIMPAN DI [FlutterSecureStorage]
/// (Android Keystore / iOS Keychain — terenkripsi hardware-backed bila
/// tersedia), BUKAN LAGI di tabel `settings` (SQLite biasa, plain text).
/// Sebelumnya siapa pun yang bisa membaca file database mentah (mis.
/// lewat `adb backup` di device yang di-debug, atau salinan file
/// `.db` dari backup tidak terenkripsi) bisa langsung membaca hash+salt
/// PIN. Walau SHA-256 tidak mudah dibalik untuk PIN 4-8 digit, ini tetap
/// kebocoran yang tidak perlu untuk sesuatu yang fungsinya adalah kunci
/// aplikasi. [_migrateLegacyPinIfNeeded] memindahkan data lama secara
/// transparan sekali saja supaya PIN yang sudah dipasang pengguna
/// sebelumnya tidak hilang saat update.
const String kSettingsKeyPinSalt = 'pin_salt';
const String kSettingsKeyPinHash = 'pin_hash';
const String kSettingsKeyAutoLockMinutes = 'autolock_minutes';

/// Toggle "buka dengan sidik jari/wajah" — HANYA sebagai ALTERNATIF PIN;
/// PIN tetap wajib terpasang sebagai fallback (lihat SecuritySettingsPage
/// dan dokumentasi [authenticateWithBiometric]).
const String kSettingsKeyBiometricEnabled = 'biometric_enabled';

/// Persist percobaan gagal PIN — lihat dokumentasi kelas: dulu in-memory
/// saja (reset saat force-close), sekarang disimpan di `settings` supaya
/// bertahan lintas restart proses.
const String kSettingsKeyPinFailedAttempts = 'pin_failed_attempts';
const String kSettingsKeyPinCooldownUntil = 'pin_cooldown_until';

/// Batas percobaan salah sebelum cooldown.
const int kMaxPinAttempts = 5;

/// Durasi cooldown setelah batas percobaan tercapai.
const int kPinCooldownSeconds = 30;

/// Repository keamanan TIPIS di atas settingsDao (READ/WRITE settings
/// saja — tanpa perubahan skema).
///
/// Cooldown percobaan PIN kini DIPERSISTEN ke `settings`
/// ([kSettingsKeyPinFailedAttempts]/[kSettingsKeyPinCooldownUntil]) —
/// bukan lagi murni in-memory. Sebelumnya, force-close aplikasi mereset
/// hitungan percobaan gagal ke 0, sehingga brute-force PIN 4-8 digit
/// jadi jauh lebih mudah (tinggal restart app tiap `kMaxPinAttempts`
/// percobaan). `_failedAttempts`/`_cooldownUntil` tetap dipertahankan
/// DI MEMORI sebagai cache SINKRON (dibaca `LockScreen` lewat getter
/// biasa, bukan `Future`), tapi dimuat dari DB sekali di awal
/// (`_ensureAttemptsLoaded`, dipicu dari constructor) dan ditulis ulang
/// ke DB setiap berubah (`_persistAttempts`) — kombinasi ini membuat
/// getter tetap sinkron/cepat sambil bertahan lintas restart proses.
class SecurityRepository {
  SecurityRepository(
    this._db, {
    BytesGenerator? randomBytes,
    DateTime Function()? clock,
    AutoLockPolicy? autoLockPolicy,
    FlutterSecureStorage? secureStorage,
    LocalAuthentication? localAuth,
  }) : _randomBytes = randomBytes,
       _clock = clock ?? DateTime.now,
       autoLockPolicy =
           autoLockPolicy ?? AutoLockPolicy(clock: clock),
       _secureStorage = secureStorage ?? const FlutterSecureStorage(),
       _localAuth = localAuth ?? LocalAuthentication() {
    // Mulai muat dari DB sedini mungkin (saat repository dibuat di
    // startup aplikasi) — di praktiknya ini selesai jauh sebelum
    // pengguna sempat mengetik PIN pertama kali (lock screen baru
    // tampil setelah timeout auto-lock terlewati).
    unawaited(_ensureAttemptsLoaded());
    unawaited(_migrateLegacyPinIfNeeded());
  }

  final AppDatabase _db;
  final BytesGenerator? _randomBytes;
  final DateTime Function() _clock;
  final FlutterSecureStorage _secureStorage;
  final LocalAuthentication _localAuth;

  /// Policy auto-lock dipakai bersama wiring gate oleh A (AppShell).
  final AutoLockPolicy autoLockPolicy;

  int _failedAttempts = 0;
  DateTime? _cooldownUntil;
  Future<void>? _loadFuture;
  Future<void>? _migrationFuture;

  /// Pindahkan `pin_salt`/`pin_hash` lama dari tabel `settings` (plain
  /// SQLite) ke [FlutterSecureStorage] — idempoten & aman dipanggil
  /// berkali-kali (panggilan kedua+ langsung no-op karena kunci lama
  /// sudah tidak ada lagi di `settings`).
  Future<void> _migrateLegacyPinIfNeeded() {
    return _migrationFuture ??= _doMigrateLegacyPin();
  }

  Future<void> _doMigrateLegacyPin() async {
    final String? legacyHash =
        await _db.settingsDao.getValue(kSettingsKeyPinHash);
    final String? legacySalt =
        await _db.settingsDao.getValue(kSettingsKeyPinSalt);
    if (legacyHash == null && legacySalt == null) return;

    if (legacyHash != null) {
      await _secureStorage.write(key: kSettingsKeyPinHash, value: legacyHash);
    }
    if (legacySalt != null) {
      await _secureStorage.write(key: kSettingsKeyPinSalt, value: legacySalt);
    }
    // Hapus jejak lama di SQLite plain text setelah berhasil dipindah.
    await _db.settingsDao.remove(kSettingsKeyPinHash);
    await _db.settingsDao.remove(kSettingsKeyPinSalt);
  }

  /// Muat `_failedAttempts`/`_cooldownUntil` dari `settings` — idempoten
  /// (panggilan kedua+ mengembalikan future yang sama, tidak query ulang).
  Future<void> _ensureAttemptsLoaded() {
    return _loadFuture ??= _loadAttemptsFromDb();
  }

  Future<void> _loadAttemptsFromDb() async {
    final String? attemptsRaw =
        await _db.settingsDao.getValue(kSettingsKeyPinFailedAttempts);
    final String? cooldownRaw =
        await _db.settingsDao.getValue(kSettingsKeyPinCooldownUntil);
    _failedAttempts = int.tryParse(attemptsRaw ?? '') ?? 0;
    final DateTime? storedCooldown =
        cooldownRaw == null ? null : DateTime.tryParse(cooldownRaw);
    // Buang cooldown yang sudah lewat waktunya supaya tidak nyangkut
    // sebagai state basi (mis. aplikasi dibuka lagi jauh setelah
    // cooldown berakhir).
    _cooldownUntil =
        (storedCooldown != null && storedCooldown.isAfter(_clock()))
            ? storedCooldown
            : null;
  }

  Future<void> _persistAttempts() async {
    await _db.settingsDao.setValue(
      kSettingsKeyPinFailedAttempts,
      '$_failedAttempts',
    );
    final DateTime? until = _cooldownUntil;
    if (until == null) {
      await _db.settingsDao.remove(kSettingsKeyPinCooldownUntil);
    } else {
      await _db.settingsDao.setValue(
        kSettingsKeyPinCooldownUntil,
        until.toIso8601String(),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // PIN
  // ---------------------------------------------------------------------------

  Future<bool> hasPin() async {
    await _migrateLegacyPinIfNeeded();
    final String? hash = await _secureStorage.read(key: kSettingsKeyPinHash);
    return hash != null && hash.isNotEmpty;
  }

  /// Simpan PIN baru: salt acak (injectable untuk test) + hash, ke
  /// [FlutterSecureStorage] (lihat dokumentasi header kelas).
  /// PIN valid: 4-8 digit.
  Future<void> setPin(String pin) async {
    if (!RegExp(r'^\d{4,8}$').hasMatch(pin)) {
      throw ArgumentError.value(pin, 'pin', 'PIN harus 4-8 digit');
    }
    final String salt = generateSalt(randomBytes: _randomBytes);
    await _secureStorage.write(key: kSettingsKeyPinSalt, value: salt);
    await _secureStorage.write(
      key: kSettingsKeyPinHash,
      value: hashPin(pin, salt),
    );
    await _resetAttempts();
  }

  /// Hapus PIN dari secure storage (auto-lock tetap tersimpan, independen).
  /// Biometrik ikut dinonaktifkan — tidak ada gunanya menyisakan alternatif
  /// biometrik tanpa PIN sebagai fallback wajib.
  Future<void> removePin() async {
    await _secureStorage.delete(key: kSettingsKeyPinHash);
    await _secureStorage.delete(key: kSettingsKeyPinSalt);
    await setBiometricEnabled(false);
    await _resetAttempts();
  }

  /// Verifikasi PIN. FALSE juga dikembalikan selama cooldown aktif.
  /// Setelah [kMaxPinAttempts] salah berturut-turut -> cooldown
  /// [kPinCooldownSeconds] detik, DIPERSISTEN ke `settings` (bertahan
  /// lintas restart proses — lihat dokumentasi kelas).
  Future<bool> verifyPin(String pin) async {
    await _ensureAttemptsLoaded();
    await _migrateLegacyPinIfNeeded();
    if (isCoolingDown) return false;

    final String? salt =
        await _secureStorage.read(key: kSettingsKeyPinSalt);
    final String? storedHash =
        await _secureStorage.read(key: kSettingsKeyPinHash);
    if (salt == null || storedHash == null || storedHash.isEmpty) {
      return false;
    }

    final bool ok = verifyPinHash(pin, salt, storedHash);
    if (ok) {
      await _resetAttempts();
      // Upgrade transparan sekali: PIN yang masih tersimpan pakai format
      // SHA-256 lama (pra-PBKDF2) dihitung ulang ke format baru begitu
      // berhasil diverifikasi — pengguna tidak perlu memasang ulang PIN,
      // tapi hash yang tersimpan langsung lebih tahan brute-force offline
      // sejak login berikutnya (lihat dokumentasi header pin_hasher.dart).
      if (isLegacyPinHash(storedHash)) {
        await _secureStorage.write(
          key: kSettingsKeyPinHash,
          value: hashPin(pin, salt),
        );
      }
      autoLockPolicy.unlockSuccess();
      return true;
    }

    _failedAttempts += 1;
    if (_failedAttempts >= kMaxPinAttempts) {
      _cooldownUntil = _clock()
          .add(const Duration(seconds: kPinCooldownSeconds));
      _failedAttempts = 0;
    }
    await _persistAttempts();
    return false;
  }

  bool get isCoolingDown {
    final DateTime? until = _cooldownUntil;
    if (until == null) return false;
    return _clock().isBefore(until);
  }

  DateTime? get cooldownUntil => _cooldownUntil;

  int get remainingCooldownSeconds {
    final DateTime? until = _cooldownUntil;
    if (until == null) return 0;
    final int remaining = until.difference(_clock()).inSeconds;
    return remaining < 0 ? 0 : remaining;
  }

  Future<void> _resetAttempts() async {
    _failedAttempts = 0;
    _cooldownUntil = null;
    await _persistAttempts();
  }

  // ---------------------------------------------------------------------------
  // Biometrik (local_auth) — alternatif PIN, TIDAK menggantikan PIN.
  // ---------------------------------------------------------------------------

  /// Perangkat mendukung + punya biometrik terdaftar (sidik jari/wajah)?
  /// Tidak melempar — kegagalan platform channel dianggap "tidak tersedia".
  Future<bool> isBiometricSupported() async {
    try {
      final bool canCheck = await _localAuth.canCheckBiometrics;
      final bool deviceSupported = await _localAuth.isDeviceSupported();
      return canCheck && deviceSupported;
    } on Exception {
      return false;
    }
  }

  /// Preferensi pengguna (toggle di SecuritySettingsPage). NOTE: ini
  /// bukan jaminan bisa dipakai — selalu pasangkan dengan
  /// [isBiometricSupported] sebelum menampilkan tombol biometrik di
  /// LockScreen.
  Future<bool> isBiometricEnabled() async {
    final String? raw =
        await _db.settingsDao.getValue(kSettingsKeyBiometricEnabled);
    return raw == 'true';
  }

  /// [enabled] hanya boleh true kalau PIN sudah terpasang (biometrik
  /// adalah ALTERNATIF, bukan pengganti — kalau sensor gagal/tidak
  /// dikenali, pengguna tetap harus punya jalan masuk lewat PIN).
  Future<void> setBiometricEnabled(bool enabled) async {
    await _db.settingsDao.setValue(
      kSettingsKeyBiometricEnabled,
      enabled ? 'true' : 'false',
    );
  }

  /// Autentikasi via BiometricPrompt (Android) / Face ID-Touch ID (iOS).
  /// Return true hanya bila: toggle aktif, perangkat mendukung, DAN
  /// pengguna berhasil diverifikasi OS. Kegagalan sensor/pembatalan
  /// pengguna/exception platform semuanya jadi `false` (fallback normal:
  /// pengguna kembali ke keypad PIN, TIDAK dihitung sebagai percobaan PIN
  /// gagal — jalur ini terpisah dari [verifyPin] dan tidak tersentuh
  /// cooldown, karena verifikasi sesungguhnya dilakukan OS, bukan
  /// dibandingkan sebagai string yang bisa di-brute-force dari sini).
  Future<bool> authenticateWithBiometric() async {
    if (!await isBiometricEnabled()) return false;
    if (!await isBiometricSupported()) return false;
    try {
      final bool ok = await _localAuth.authenticate(
        localizedReason: 'Buka Transaction Journey',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
      if (ok) autoLockPolicy.unlockSuccess();
      return ok;
    } on Exception {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Auto-lock timeout (settings autolock_minutes)
  // ---------------------------------------------------------------------------

  /// Nilai mentah setting; NULL = belum pernah diset (pemanggil dapat
  /// memakai `AutoLockPolicy.kDefaultAutoLockMinutes`).
  Future<int?> getAutoLockSetting() async {
    final String? raw =
        await _db.settingsDao.getValue(kSettingsKeyAutoLockMinutes);
    if (raw == null) return null;
    return int.tryParse(raw);
  }

  /// Nilai efektif untuk policy: setting tersimpan atau default 2 menit.
  /// 0 = langsung; nilai >= 1 = menit. Nonaktif penuh ditangani policy
  /// lewat setTimeoutMinutes(null) di memori (tidak dipersistenkan
  /// repository ini).
  Future<int> autoLockMinutesOrDefault() async =>
      await getAutoLockSetting() ?? AutoLockPolicy.kDefaultAutoLockMinutes;

  Future<void> setAutoLockMinutes(int? minutes) async {
    if (minutes == null) {
      await _db.settingsDao.remove(kSettingsKeyAutoLockMinutes);
      return;
    }
    if (minutes < 0) {
      throw ArgumentError.value(minutes, 'minutes', 'Tidak boleh negatif');
    }
    await _db.settingsDao.setValue(
      kSettingsKeyAutoLockMinutes,
      '$minutes',
    );
  }
}
