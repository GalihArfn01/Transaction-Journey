import '../../domain/model/enums.dart';

/// Data awal (seed) yang dijamin ada saat aplikasi pertama dibuka.
///
/// Icon disimpan sebagai key string, dipetakan ke IconData oleh
/// `AppIconRegistry` di layer presentation — DB tidak menyimpan objek UI.

class SeedCategory {
  const SeedCategory(this.name, this.type, this.icon, this.colorValue);

  final String name;
  final TransactionType type;
  final String icon;
  final int colorValue;
}

class SeedPaymentMethod {
  const SeedPaymentMethod(this.name, this.icon);

  final String name;
  final String icon;
}

class SeedAccount {
  const SeedAccount(
    this.name,
    this.type,
    this.icon,
    this.colorValue,
    this.initialBalanceMinor,
  );

  final String name;
  final AccountType type;
  final String icon;
  final int colorValue;
  final int initialBalanceMinor;
}

/// Kategori pengeluaran default (sesuai requirement).
const List<SeedCategory> kDefaultExpenseCategories = [
  SeedCategory('Makanan', TransactionType.expense, 'restaurant', 0xFFEF6C00),
  SeedCategory('Transportasi', TransactionType.expense, 'commute', 0xFF1E88E5),
  SeedCategory('Belanja', TransactionType.expense, 'shopping_bag', 0xFFD81B60),
  SeedCategory('Tagihan', TransactionType.expense, 'receipt_long', 0xFF8E24AA),
  SeedCategory('Hiburan', TransactionType.expense, 'movie', 0xFFFBC02D),
  SeedCategory('Kesehatan', TransactionType.expense, 'medical_services', 0xFFE53935),
  SeedCategory('Pendidikan', TransactionType.expense, 'school', 0xFF00ACC1),
  SeedCategory('Internet', TransactionType.expense, 'wifi', 0xFF43A047),
  SeedCategory('Pulsa', TransactionType.expense, 'smartphone', 0xFF6D4C41),
  SeedCategory('Tempat Tinggal', TransactionType.expense, 'home_work', 0xFF5E35B1),
  SeedCategory('Investasi', TransactionType.expense, 'savings', 0xFF2E7D32),
  SeedCategory('Lainnya', TransactionType.expense, 'more_horiz', 0xFF757575),
];

/// Kategori pemasukan default (sesuai requirement).
const List<SeedCategory> kDefaultIncomeCategories = [
  SeedCategory('Gaji', TransactionType.income, 'payments', 0xFF2E7D32),
  SeedCategory('Bonus', TransactionType.income, 'stars', 0xFFF9A825),
  SeedCategory('Freelance', TransactionType.income, 'laptop_mac', 0xFF00897B),
  SeedCategory('Bisnis', TransactionType.income, 'storefront', 0xFF3949AB),
  SeedCategory('Investasi', TransactionType.income, 'trending_up', 0xFF039BE5),
  SeedCategory('Hadiah', TransactionType.income, 'redeem', 0xFFD81B60),
  SeedCategory('Lainnya', TransactionType.income, 'more_horiz', 0xFF757575),
];

/// Metode pembayaran default (sesuai requirement).
const List<SeedPaymentMethod> kDefaultPaymentMethods = [
  SeedPaymentMethod('Tunai', 'payments'),
  SeedPaymentMethod('Transfer Bank', 'account_balance'),
  SeedPaymentMethod('E-Wallet', 'account_balance_wallet'),
  SeedPaymentMethod('Kartu Debit', 'credit_card'),
  SeedPaymentMethod('Kartu Kredit', 'credit_score'),
  SeedPaymentMethod('Lainnya', 'more_horiz'),
];

/// Rekening TETAP — hanya 2, TIDAK BISA ditambah/dihapus dari UI (lihat
/// `AccountsPage`): "Tunai" untuk uang fisik, "Non Tunai" untuk semua
/// uang digital (mBanking, DANA, GoPay, ShopeePay, OVO, dll — apa pun
/// yang terdeteksi lewat notifikasi otomatis SELALU masuk ke sini, lihat
/// dokumentasi `AccountType`).
const List<SeedAccount> kDefaultAccounts = [
  SeedAccount('Tunai', AccountType.cash, 'wallet', 0xFF00695C, 0),
  SeedAccount(
    'Non Tunai',
    AccountType.nonCash,
    'account_balance_wallet',
    0xFF1565C0,
    0,
  ),
];

class SeedNotificationSource {
  const SeedNotificationSource(
    this.appName,
    this.packageName,
    this.parserType,
  );

  final String appName;
  final String packageName;
  final String parserType;
}

/// Aplikasi keuangan populer Indonesia. Semua DISABLED secara default —
/// pengguna yang memutuskan aplikasi mana yang dipantau.
/// Package name best-effort dan dapat dikoreksi pengguna di UI nanti.
const List<SeedNotificationSource> kDefaultNotificationSources = [
  // SEBELUMNYA package name-nya 'com.bca' — TERVERIFIKASI SALAH (dicek
  // langsung ke listing Play Store): itu bukan id package Android yang
  // valid untuk aplikasi resmi apa pun, cuma tebakan. Aplikasi resmi BCA
  // saat ini bernama "myBCA" dengan package name
  // 'com.bca.mybca.omni.android' — ini yang menyebabkan notifikasi BCA
  // tidak pernah terbaca (packageName di `NotificationCaptureService`
  // tidak pernah cocok dengan notifikasi asli dari HP). Lihat migrasi
  // schemaVersion 5 di `app_database.dart` yang memperbaiki baris ini
  // untuk instalasi yang SUDAH ADA (seed hanya jalan sekali saat tabel
  // masih kosong, jadi perbaikan di sini saja tidak cukup untuk pengguna
  // yang sudah pernah membuka app).
  SeedNotificationSource('myBCA', 'com.bca.mybca.omni.android', 'bca'),
  SeedNotificationSource('BRImo', 'id.co.brimo.brimo', 'brimo'),
  SeedNotificationSource("Livin' by Mandiri", 'com.bankmandiri.mandirionline', 'livin'),
  SeedNotificationSource('BNI Mobile Banking', 'src.com.bni', 'generic'),
  SeedNotificationSource('DANA', 'id.dana', 'dana'),
  SeedNotificationSource('Gojek / GoPay', 'com.gojek.app', 'gopay'),
  SeedNotificationSource('OVO', 'id.ovo', 'ovo'),
  SeedNotificationSource('Shopee', 'com.shopee.id', 'generic'),
  SeedNotificationSource('LinkAja', 'id.linkaja.app', 'generic'),
];

/// Settings default (key, value).
///
/// `theme_mode` SENGAJA tidak ada di sini lagi: dark mode dihapus permanen
/// (aplikasi selalu terang, lihat `AppTheme`), jadi tidak ada pengaturan
/// tema yang perlu di-seed. Baris `theme_mode` pada instalasi lama yang
/// sudah terlanjur ada dibiarkan (tidak dibaca siapa pun, tidak
/// mengganggu) — tidak ada migrasi penghapusan khusus untuknya.
const Map<String, String> kDefaultSettings = {};
