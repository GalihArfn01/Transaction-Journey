/// Privasi saldo — kunci pengaturan & teks penyamar bersama oleh
/// dashboard, payload widget, dan (lewat payload) native AppWidget.
library;

/// Kunci di tabel `settings`; nilai '1' = saldo disembunyikan.
const String kHideBalanceSettingKey = 'hide_balance';

/// Teks pengganti nominal saat saldo disembunyikan. HARUS identik dengan
/// `HIDDEN_BALANCE_TEXT` di `WidgetPrefs.kt`.
const String kHiddenBalanceText = 'Rp $kHiddenBalanceDigits';

/// Bagian penyamar TANPA "Rp" — dipakai hero Total Saldo di dashboard,
/// yang menggambar "Rp" sebagai teks statis terpisah supaya tidak ikut
/// memudar/bergeser saat tombol mata ditekan.
const String kHiddenBalanceDigits = '••••••';

/// Parse nilai mentah setting -> bool (null/selain '1' = tampil).
bool parseHideBalance(String? raw) => raw == '1';
