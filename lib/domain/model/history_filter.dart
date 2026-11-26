import '../../core/utils/period.dart';
import '../model/enums.dart';

/// Urutan penyortiran daftar transaksi.
enum HistorySortField { date, amount }

/// Mode pengelompokan riwayat.
enum HistoryGrouping { day, week, month, year }

/// Filter halaman riwayat. Pure data — mudah diuji & dibandingkan.
class HistoryFilter {
  const HistoryFilter({
    this.range,
    this.type,
    this.categoryId,
    this.accountId,
    this.paymentMethodId,
    this.query = '',
    this.sortField = HistorySortField.date,
    this.sortAscending = false,
    this.grouping = HistoryGrouping.day,
  });

  /// NULL = semua waktu.
  final DateRange? range;
  final TransactionType? type;
  final int? categoryId;
  final int? accountId;
  final int? paymentMethodId;

  /// Kata kunci pencarian: catatan, nama kategori, nama rekening,
  /// nama tag, atau nominal (bila berupa angka).
  final String query;
  final HistorySortField sortField;
  final bool sortAscending;
  final HistoryGrouping grouping;

  bool get isDefault =>
      range == null &&
      type == null &&
      categoryId == null &&
      accountId == null &&
      paymentMethodId == null &&
      query.trim().isEmpty;

  /// Jumlah filter aktif (untuk badge di UI); query dihitung terpisah.
  int get activeFilterCount {
    int n = 0;
    if (range != null) n++;
    if (type != null) n++;
    if (categoryId != null) n++;
    if (accountId != null) n++;
    if (paymentMethodId != null) n++;
    if (query.trim().isNotEmpty) n++;
    return n;
  }

  HistoryFilter copyWith({
    Object? range = _sentinel,
    Object? type = _sentinel,
    Object? categoryId = _sentinel,
    Object? accountId = _sentinel,
    Object? paymentMethodId = _sentinel,
    String? query,
    HistorySortField? sortField,
    bool? sortAscending,
    HistoryGrouping? grouping,
  }) =>
      HistoryFilter(
        range: range == _sentinel ? this.range : range as DateRange?,
        type: type == _sentinel ? this.type : type as TransactionType?,
        categoryId:
            categoryId == _sentinel ? this.categoryId : categoryId as int?,
        accountId:
            accountId == _sentinel ? this.accountId : accountId as int?,
        paymentMethodId: paymentMethodId == _sentinel
            ? this.paymentMethodId
            : paymentMethodId as int?,
        query: query ?? this.query,
        sortField: sortField ?? this.sortField,
        sortAscending: sortAscending ?? this.sortAscending,
        grouping: grouping ?? this.grouping,
      );

  static const Object _sentinel = Object();
}
