/// Payload data untuk widget layar utama (native AppWidget) — PURE.
///
/// Tanpa I/O dan TANPA package home_widget (keputusan A): payload
/// di-serialisasi ke JSON sehingga lapisan native cukup membaca
/// string/SharedPreferences. Semua nominal int rupiah utuh (*Minor).
library;

/// Satu baris rekening untuk widget Saldo — versi ringkas dari
/// `AccountWithBalance` (domain/data layer) yang aman diserialisasi ke JSON
/// dan dikirim ke native.
class WidgetAccountSnapshot {
  const WidgetAccountSnapshot({
    required this.id,
    required this.name,
    required this.balanceMinor,
    required this.icon,
  });

  final int id;
  final String name;
  final int balanceMinor;

  /// Kunci ikon ringkas untuk native (bukan `IconData` Flutter):
  /// 'bank' | 'wallet' | 'ewallet' | 'other'. Lihat `AccountType` di
  /// enums.dart — native memetakan ini ke vector drawable masing-masing.
  final String icon;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'balanceMinor': balanceMinor,
        'icon': icon,
      };

  factory WidgetAccountSnapshot.fromJson(Map<String, dynamic> json) {
    return WidgetAccountSnapshot(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String,
      balanceMinor: (json['balanceMinor'] as num).toInt(),
      icon: json['icon'] as String,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is WidgetAccountSnapshot &&
      other.id == id &&
      other.name == name &&
      other.balanceMinor == balanceMinor &&
      other.icon == icon;

  @override
  int get hashCode => Object.hash(id, name, balanceMinor, icon);
}

/// Satu kategori untuk chip "Kategori" widget Saldo — id + nama saja;
/// pencocokan tipe (income/expense) terjadi di `WidgetDataRepository`
/// saat transaksi dibuat, native tidak perlu tahu tipenya.
class WidgetCategorySnapshot {
  const WidgetCategorySnapshot({
    required this.id,
    required this.name,
  });

  final int id;
  final String name;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
      };

  factory WidgetCategorySnapshot.fromJson(Map<String, dynamic> json) {
    return WidgetCategorySnapshot(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is WidgetCategorySnapshot && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);
}

/// Snapshot ringkas untuk homescreen widget — dua kartu: Saldo (CRUD cepat
/// per rekening) dan Ringkasan Harian (income/expense hari berjalan).
class HomeWidgetPayload {
  const HomeWidgetPayload({
    required this.balanceMinor,
    this.todayIncomeMinor = 0,
    required this.todayExpenseMinor,
    required this.weekExpenseMinor,
    required this.monthExpenseMinor,
    this.accounts = const <WidgetAccountSnapshot>[],
    this.categories = const <WidgetCategorySnapshot>[],
    required this.generatedAt,
    this.hideBalance = false,
  });

  final int balanceMinor;
  final int todayIncomeMinor;
  final int todayExpenseMinor;
  final int weekExpenseMinor;
  final int monthExpenseMinor;

  /// Rekening aktif diurutkan menurut saldo terbesar — widget native
  /// menampilkan maksimum 2 baris pertama (lihat catatan desain
  /// `Home Screen Widgets.dc.html`, `hint-placeholder-count="2"`).
  final List<WidgetAccountSnapshot> accounts;

  /// Kategori aktif untuk chip siklus "Kategori" widget Saldo — index 0
  /// selalu "Tanpa kategori" (implisit, tidak dikirim).
  final List<WidgetCategorySnapshot> categories;

  /// Waktu snapshot dibuat — ditampilkan native sebagai "diperbarui HH:mm"
  /// dan dipakai untuk membuang payload terlalu tua.
  final DateTime generatedAt;

  /// Pengguna memilih menyembunyikan saldo — native menampilkan
  /// `Rp ••••••` sebagai ganti nominal saldo (total & per rekening).
  final bool hideBalance;

  int get netTodayMinor => todayIncomeMinor - todayExpenseMinor;

  /// Proporsi pemasukan hari ini (0-100), dipakai bar Ringkasan Harian.
  /// 50 bila belum ada mutasi hari ini (bar netral, bukan kosong/penuh).
  int get incomeSharePercent {
    final int total = todayIncomeMinor + todayExpenseMinor;
    if (total <= 0) return 50;
    return ((todayIncomeMinor * 100) / total).round().clamp(0, 100);
  }

  /// Konstruktor praktis: generatedAt otomatis sekarang.
  factory HomeWidgetPayload.fromParts({
    required int balanceMinor,
    int todayIncomeMinor = 0,
    required int todayExpenseMinor,
    required int weekExpenseMinor,
    required int monthExpenseMinor,
    List<WidgetAccountSnapshot> accounts = const <WidgetAccountSnapshot>[],
    List<WidgetCategorySnapshot> categories =
        const <WidgetCategorySnapshot>[],
    bool hideBalance = false,
  }) {
    return HomeWidgetPayload(
      balanceMinor: balanceMinor,
      todayIncomeMinor: todayIncomeMinor,
      todayExpenseMinor: todayExpenseMinor,
      weekExpenseMinor: weekExpenseMinor,
      monthExpenseMinor: monthExpenseMinor,
      accounts: accounts,
      categories: categories,
      generatedAt: DateTime.now(),
      hideBalance: hideBalance,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'balanceMinor': balanceMinor,
        'todayIncomeMinor': todayIncomeMinor,
        'todayExpenseMinor': todayExpenseMinor,
        'weekExpenseMinor': weekExpenseMinor,
        'monthExpenseMinor': monthExpenseMinor,
        'accounts': accounts.map((WidgetAccountSnapshot a) => a.toJson()).toList(),
        'categories':
            categories.map((WidgetCategorySnapshot c) => c.toJson()).toList(),
        'generatedAt': generatedAt.toIso8601String(),
        'hideBalance': hideBalance,
      };

  /// Strict decode — throw bila field hilang/format salah.
  /// Untuk data dari native yang mungkin korup pakai [tryFromJson].
  factory HomeWidgetPayload.fromJson(Map<String, dynamic> json) {
    return HomeWidgetPayload(
      // `as num` menoleransi JSON number yang ter-decode double.
      balanceMinor: (json['balanceMinor'] as num).toInt(),
      todayIncomeMinor: (json['todayIncomeMinor'] as num? ?? 0).toInt(),
      todayExpenseMinor: (json['todayExpenseMinor'] as num).toInt(),
      weekExpenseMinor: (json['weekExpenseMinor'] as num).toInt(),
      monthExpenseMinor: (json['monthExpenseMinor'] as num).toInt(),
      accounts: (json['accounts'] as List<dynamic>? ?? const <dynamic>[])
          .map(
            (dynamic e) =>
                WidgetAccountSnapshot.fromJson(e as Map<String, dynamic>),
          )
          .toList(),
      categories: (json['categories'] as List<dynamic>? ?? const <dynamic>[])
          .map(
            (dynamic e) =>
                WidgetCategorySnapshot.fromJson(e as Map<String, dynamic>),
          )
          .toList(),
      generatedAt: DateTime.parse(json['generatedAt'] as String),
      hideBalance: json['hideBalance'] as bool? ?? false,
    );
  }

  /// Decode aman: NULL bila payload tidak valid (field kurang / format
  /// rusak) — jangan pernah biarkan widget crash karena data basi.
  static HomeWidgetPayload? tryFromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    try {
      return HomeWidgetPayload.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is HomeWidgetPayload &&
      other.balanceMinor == balanceMinor &&
      other.todayIncomeMinor == todayIncomeMinor &&
      other.todayExpenseMinor == todayExpenseMinor &&
      other.weekExpenseMinor == weekExpenseMinor &&
      other.monthExpenseMinor == monthExpenseMinor &&
      other.generatedAt == generatedAt &&
      other.hideBalance == hideBalance;

  @override
  int get hashCode => Object.hash(balanceMinor, todayIncomeMinor,
      todayExpenseMinor, weekExpenseMinor, monthExpenseMinor, generatedAt,
      hideBalance);

  @override
  String toString() => 'HomeWidgetPayload(${toJson()})';
}
