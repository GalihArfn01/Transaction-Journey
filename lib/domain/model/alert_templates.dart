/// Template notifikasi per-budget (v6) — murni, tanpa I/O (aturan AQ #15).
///
/// User dapat mengatur bebas judul & isi notifikasi untuk budget
/// masing-masing kategori (mis. "Kamu sudah terlalu banyak jajan hari
/// ini..."). Placeholder diganti sistem saat notifikasi dikirim:
///
/// - `{kategori}` — nama kategori (atau "Semua kategori" bila budget
///   keseluruhan).
/// - `{terpakai}` — total pemakaian periode ini, mis. `Rp25.000`.
/// - `{batas}` — nominal batas budget, mis. `Rp50.000`.
/// - `{sisa}` — sisa batas (negatif bila over, mis. `-Rp10.000`).
/// - `{persen}` — persentase pemakaian, mis. `50%` / `120%`.
///
/// Nilai nominal SUDAH termasuk simbol `Rp` — jangan menulis `Rp{terpakai}`
/// (dobel). Template kosong/null = pakai default. Placeholder tak dikenal
/// dibiarkan apa adanya; teks polos tanpa placeholder dikirim apa
/// adanya.
library;

import '../../core/utils/money_formatter.dart';

/// Placeholder yang dijanjikan ke user (dipakai UI untuk hint & chips).
const List<String> kAlertPlaceholders = [
  '{kategori}',
  '{terpakai}',
  '{batas}',
  '{sisa}',
  '{persen}',
];

const String kDefaultAlertTitle = 'Batasi pengeluaran {kategori}';
const String kDefaultAlertBody =
    'Terpakai {terpakai} dari batas {batas} ({persen}). Sisa {sisa}.';

/// Data yang dibutuhkan untuk merender template alert budget.
class AlertTemplateValues {
  const AlertTemplateValues({
    required this.categoryName,
    required this.spentMinor,
    required this.limitMinor,
  });

  final String categoryName;
  final int spentMinor;
  final int limitMinor;

  Map<String, String> _toMap() {
    final int percent =
        limitMinor <= 0 ? 0 : (spentMinor * 100 / limitMinor).round();
    return <String, String>{
      '{kategori}': categoryName,
      '{terpakai}': MoneyFormatter.format(spentMinor),
      '{batas}': MoneyFormatter.format(limitMinor),
      '{sisa}': MoneyFormatter.format(limitMinor - spentMinor),
      '{persen}': '$percent%',
    };
  }
}

/// Ganti semua placeholder yang dikenal di [template].
///
/// Nilai `null`/kosong dianggap tidak diisi user -> [fallback]
/// (default bawaan) yang dipakai. Placeholder tak dikenal dibiarkan.
String renderAlertTemplate(
  String? template,
  String fallback,
  AlertTemplateValues values,
) {
  String result = (template == null || template.trim().isEmpty)
      ? fallback
      : template;
  values._toMap().forEach((String key, String value) {
    result = result.replaceAll(key, value);
  });
  return result;
}

/// Judul notifikasi untuk budget (custom user atau default).
String renderAlertTitle(String? template, AlertTemplateValues values) =>
    renderAlertTemplate(template, kDefaultAlertTitle, values);

/// Isi notifikasi untuk budget (custom user atau default).
String renderAlertBody(String? template, AlertTemplateValues values) =>
    renderAlertTemplate(template, kDefaultAlertBody, values);

/// Sisi pemakaian relatif ambang pemicu — untuk anti-spam transisi.
///
/// Mengembalikan `'over'` bila pemakaian sudah mencapai [triggerMinor]
/// rupiah, selain itu `'under'`. Dibandingkan dengan nilai tersimpan
/// (`Budgets.alertLastSide`); notifikasi hanya dikirim saat berpindah ke
/// `'over'` — sama seperti pola skor kesehatan di `HealthReminderService`.
///
/// [triggerMinor] <= 0 selalu `'under'` (tidak pernah memicu — pemanggil
/// bertanggung jawab mengisi fallback batas budget bila ambang NULL).
String alertSideOf(int spentMinor, int triggerMinor) =>
    triggerMinor > 0 && spentMinor >= triggerMinor ? 'over' : 'under';
