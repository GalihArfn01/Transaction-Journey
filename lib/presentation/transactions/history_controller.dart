import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/period.dart';
import '../../data/datasource/database_provider.dart';
import '../../data/datasource/dao/transaction_dao.dart';
import '../../domain/model/enums.dart';
import '../../domain/model/history_filter.dart';

/// Debounce pencarian riwayat — menahan query SQL sampai pengguna
/// berhenti mengetik.
const Duration kHistorySearchDebounce = Duration(milliseconds: 300);

/// Controller filter halaman riwayat. Satu sumber kebenaran untuk
/// pencarian, filter, sort, dan grouping. Mutasi state memicu
/// [filteredTransactionsProvider] menjalankan ulang query.
class HistoryFilterController extends Notifier<HistoryFilter> {
  Timer? _debounce;

  @override
  HistoryFilter build() {
    ref.onDispose(_cancelDebounce);
    return const HistoryFilter();
  }

  void _cancelDebounce() {
    _debounce?.cancel();
    _debounce = null;
  }

  void _set(HistoryFilter next) => state = next;

  void setRange(DateRange? range) => _set(state.copyWith(range: range));

  void setType(TransactionType? type) => _set(state.copyWith(type: type));

  void setCategory(int? categoryId) =>
      _set(state.copyWith(categoryId: categoryId));

  void setAccount(int? accountId) =>
      _set(state.copyWith(accountId: accountId));

  void setPaymentMethod(int? paymentMethodId) =>
      _set(state.copyWith(paymentMethodId: paymentMethodId));

  void setSort(HistorySortField field, {required bool ascending}) =>
      _set(
        state.copyWith(sortField: field, sortAscending: ascending),
      );

  void setGrouping(HistoryGrouping grouping) =>
      _set(state.copyWith(grouping: grouping));

  /// Pencarian dengan debounce 300ms — timer sebelumnya selalu dibatalkan
  /// agar hanya ketikan terakhir yang dieksekusi ke SQL.
  void setQuery(String raw) {
    _debounce?.cancel();
    _debounce = Timer(kHistorySearchDebounce, () {
      _applyQuery(raw);
      _debounce = null;
    });
  }

  /// Terapkan query seketika tanpa debounce (dipakai clearAll & tutup
  /// bar pencarian agar tidak ada query basi tertinggal).
  void applyQueryNow(String raw) {
    _debounce?.cancel();
    _debounce = null;
    _applyQuery(raw);
  }

  void _applyQuery(String raw) {
    final String trimmed = raw.trim();
    if (trimmed == state.query.trim()) return;
    _set(state.copyWith(query: trimmed));
  }

  /// Reset semua filter/pencarian/sort. Mode grouping dipertahankan —
  /// itu preferensi tampilan, bukan filter data.
  void clearAll() {
    _debounce?.cancel();
    _debounce = null;
    _set(
      HistoryFilter(grouping: state.grouping),
    );
  }
}

final NotifierProvider<HistoryFilterController, HistoryFilter>
    historyFilterProvider =
    NotifierProvider<HistoryFilterController, HistoryFilter>(
  HistoryFilterController.new,
);

/// Daftar transaksi terfilter + reaktif terhadap perubahan DB.
///
/// Emisi pertama berasal dari fetch langsung di dalam
/// `TransactionDao.watchFiltered` (pola BP-08), sehingga tidak pernah
/// macet AsyncLoading di widget-test.
final StreamProvider<List<TransactionWithRefs>> filteredTransactionsProvider =
    StreamProvider<List<TransactionWithRefs>>((Ref ref) {
  final HistoryFilter filter = ref.watch(historyFilterProvider);
  return ref.watch(appDatabaseProvider).transactionDao.watchFiltered(filter);
});
