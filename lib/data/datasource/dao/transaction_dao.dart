import 'package:drift/drift.dart';

import '../../../domain/model/enums.dart';
import '../../../domain/model/history_filter.dart';
import '../../../core/utils/period.dart';
import '../app_database.dart';
import '../tables.dart';

part 'transaction_dao.g.dart';
/// Hasil agregasi pemasukan/pengeluaran dalam rentang waktu.
class PeriodTotals {
  const PeriodTotals({required this.incomeMinor, required this.expenseMinor});

  final int incomeMinor;
  final int expenseMinor;

  int get balanceMinor => incomeMinor - expenseMinor;
}

/// Satu titik deret bulanan untuk chart analytics (Phase R6).
class MonthSeriesPoint {
  const MonthSeriesPoint({
    required this.monthStart,
    required this.incomeMinor,
    required this.expenseMinor,
  });

  /// Awal bulan (00:00) sebagai identitas titik.
  final DateTime monthStart;
  final int incomeMinor;
  final int expenseMinor;

  int get netMinor => incomeMinor - expenseMinor;
}
/// Baris hasil gabungan transaksi + referensi untuk tampilan list/detail.
class TransactionWithRefs {
  const TransactionWithRefs({
    required this.transaction,
    required this.account,
    this.category,
    this.toAccount,
    this.paymentMethod,
  });

  final Transaction transaction;
  final Category? category;
  final Account account;
  final Account? toAccount;
  final PaymentMethod? paymentMethod;
}

@DriftAccessor(tables: [Transactions, TransactionTags, Tags])
class TransactionDao extends DatabaseAccessor<AppDatabase>
    with _$TransactionDaoMixin {
  TransactionDao(super.db);

  Expression<bool> _notDeleted() => transactions.deletedAt.isNull();

  Expression<bool> _inRange(DateTime start, DateTime end) =>
      transactions.date.isBiggerOrEqualValue(start) &
      transactions.date.isSmallerThanValue(end);

  /// Daftar transaksi terbaru beserta kategori/rekening/metode bayar.
  /// Referensi di-stitch di Dart lewat query IN() per tabel — menghindari
  /// kerumitan generik join builder dan tetap efisien (indexed lookup).
  Future<List<TransactionWithRefs>> _stitchRefs(
    List<Transaction> txs,
  ) async {
    final Set<int> categoryIds = <int>{
      for (final Transaction t in txs)
        if (t.categoryId != null) t.categoryId!,
    };
    final Set<int> accountIds = <int>{for (final Transaction t in txs) t.accountId};
    final Set<int> toAccountIds = <int>{
      for (final Transaction t in txs)
        if (t.toAccountId != null) t.toAccountId!,
    };
    final Set<int> pmIds = <int>{
      for (final Transaction t in txs)
        if (t.paymentMethodId != null) t.paymentMethodId!,
    };

    final Map<int, Category> cats = categoryIds.isEmpty
        ? const <int, Category>{}
        : <int, Category>{
            for (final Category c
                in await (select(categories)
                      ..where((Categories c) => c.id.isIn(categoryIds)))
                    .get())
              c.id: c,
          };
    final Map<int, Account> accs = <int, Account>{
      for (final Account a in await (select(accounts)
            ..where((Accounts a) => a.id.isIn(accountIds.union(toAccountIds))))
          .get())
        a.id: a,
    };
    final Map<int, PaymentMethod> pms = pmIds.isEmpty
        ? const <int, PaymentMethod>{}
        : <int, PaymentMethod>{
            for (final PaymentMethod p
                in await (select(paymentMethods)
                      ..where((PaymentMethods p) => p.id.isIn(pmIds)))
                    .get())
              p.id: p,
          };

    return <TransactionWithRefs>[
      for (final Transaction t in txs)
        TransactionWithRefs(
          transaction: t,
          category: t.categoryId == null ? null : cats[t.categoryId],
          account: accs[t.accountId]!,
          toAccount: t.toAccountId == null ? null : accs[t.toAccountId],
          paymentMethod:
              t.paymentMethodId == null ? null : pms[t.paymentMethodId],
        ),
    ];
  }

  Stream<List<TransactionWithRefs>> watchDetailed({
    DateTime? start,
    DateTime? end,
    int? limit = 200,
  }) {
    final query = select(transactions)
      ..where((Transactions t) => t.deletedAt.isNull())
      ..orderBy([
        (Transactions t) => OrderingTerm.desc(t.date),
        (Transactions t) => OrderingTerm.desc(t.id),
      ]);
    if (start != null) {
      query.where((Transactions t) => t.date.isBiggerOrEqualValue(start));
    }
    if (end != null) {
      query.where((Transactions t) => t.date.isSmallerThanValue(end));
    }
    if (limit != null) {
      query.limit(limit);
    }
    return query.watch().asyncMap(_stitchRefs);
  }

  Future<List<TransactionWithRefs>> detailedList({
    DateTime? start,
    DateTime? end,
    int? limit,
  }) async {
    final query = select(transactions)
      ..where((Transactions t) => t.deletedAt.isNull())
      ..orderBy([
        (Transactions t) => OrderingTerm.desc(t.date),
        (Transactions t) => OrderingTerm.desc(t.id),
      ]);
    if (start != null) {
      query.where((Transactions t) => t.date.isBiggerOrEqualValue(start));
    }
    if (end != null) {
      query.where((Transactions t) => t.date.isSmallerThanValue(end));
    }
    if (limit != null) {
      query.limit(limit);
    }
    return _stitchRefs(await query.get());
  }


  /// Satu pass SQL dengan SUM(CASE): atomik & efisien.
  /// Index enum: 0=income, 1=expense (lihat enums.dart).
  Selectable<QueryRow> _totalsQuery(DateTime start, DateTime end) => customSelect(
        '''
        SELECT IFNULL(SUM(CASE WHEN type = ? THEN amount_minor END), 0)
                 AS income_minor,
               IFNULL(SUM(CASE WHEN type = ? THEN amount_minor END), 0)
                 AS expense_minor
        FROM transactions
        WHERE deleted_at IS NULL
          AND type != ?
          AND source != ?
          AND date >= ? AND date < ?
        ''',
        variables: [
          Variable.withInt(TransactionType.income.index),
          Variable.withInt(TransactionType.expense.index),
          Variable.withInt(TransactionType.transfer.index),
          // Setor/tarik dana goal (lihat TxnSource.goalContribution) BUKAN
          // pemasukan/pengeluaran riil — itu cuma uang berpindah antara
          // "bisa dibelanjakan" dan "ditabung", jadi dikecualikan di sini
          // supaya tidak dihitung dobel di ringkasan income/expense.
          Variable.withInt(TxnSource.goalContribution.index),
          Variable.withDateTime(start),
          Variable.withDateTime(end),
        ],
        readsFrom: {transactions},
      );

  Future<PeriodTotals> totalsBetween(DateTime start, DateTime end) async {
    final QueryRow row = await _totalsQuery(start, end).getSingle();
    return PeriodTotals(
      incomeMinor: row.read<int>('income_minor'),
      expenseMinor: row.read<int>('expense_minor'),
    );
  }

  /// Versi reactive dari [totalsBetween] — UI otomatis refresh.
  Stream<PeriodTotals> watchTotalsBetween(DateTime start, DateTime end) {
    return _totalsQuery(start, end).watchSingle().map(
          (QueryRow row) => PeriodTotals(
            incomeMinor: row.read<int>('income_minor'),
            expenseMinor: row.read<int>('expense_minor'),
          ),
        );
  }

  /// Total per kategori untuk satu jenis transaksi (terbesar dulu di repo).
  Future<Map<int, int>> categoryTotalsMinor(
    TransactionType type,
    DateTime start,
    DateTime end,
  ) async {
    final sumAmount = transactions.amountMinor.sum();
    final query = selectOnly(transactions)
      ..addColumns([transactions.categoryId, sumAmount])
      ..where(
        _notDeleted() &
            _inRange(start, end) &
            transactions.type.equalsValue(type) &
            transactions.categoryId.isNotNull(),
      )
      ..groupBy([transactions.categoryId]);

    final Map<int, int> result = <int, int>{};
    for (final TypedResult row in await query.get()) {
      final int? categoryId = row.read(transactions.categoryId);
      final int? total = row.read(sumAmount);
      if (categoryId != null) {
        result[categoryId] = total ?? 0;
      }
    }
    return result;
  }

  Stream<List<Transaction>> watchRecent({int limit = 10}) {
    return (select(transactions)
          ..where((Transactions t) => t.deletedAt.isNull())
          ..orderBy([
            (Transactions t) => OrderingTerm(
                  expression: t.date,
                  mode: OrderingMode.desc,
                ),
                (Transactions t) => OrderingTerm(
                  expression: t.id,
                  mode: OrderingMode.desc,
                ),
          ])
          ..limit(limit))
        .watch();
  }

  Future<Transaction?> byId(int id) {
    return (select(transactions)..where((Transactions t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<int> insertTransaction(TransactionsCompanion entry) =>
      into(transactions).insert(entry);

  Future<int> updateTransaction(int id, TransactionsCompanion entry) {
    return (update(transactions)..where((Transactions t) => t.id.equals(id)))
        .write(entry);
  }

  /// Soft delete — data tetap ada untuk audit; semua laporan mengabaikannya.
  Future<void> softDelete(int id) async {
    final DateTime now = DateTime.now();
    await (update(transactions)..where((Transactions t) => t.id.equals(id)))
        .write(
      TransactionsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
  }

  Future<void> restore(int id) async {
    final DateTime now = DateTime.now();
    await (update(transactions)..where((Transactions t) => t.id.equals(id)))
        .write(
      TransactionsCompanion(
        deletedAt: const Value<DateTime?>(null),
        updatedAt: Value(now),
      ),
    );
  }

  /// Duplikat transaksi: field sama, id baru + tag tersalin.
  Future<Transaction> duplicate(int id) async {
    return transaction(() async {
      final Transaction? source = await byId(id);
      if (source == null) {
        throw StateError('Transaksi $id tidak ditemukan');
      }
      final TransactionsCompanion copy = TransactionsCompanion.insert(
        type: source.type,
        amountMinor: source.amountMinor,
        date: source.date,
        categoryId: Value(source.categoryId),
        accountId: source.accountId,
        toAccountId: Value(source.toAccountId),
        paymentMethodId: Value(source.paymentMethodId),
        note: Value(source.note),
        attachmentPath: Value(source.attachmentPath),
      );
      final int newId = await into(transactions).insert(copy);

      // Salin relasi tag (dua query sederhana, tanpa join builder).
      final List<TransactionTag> links = await (select(transactionTags)
              ..where(
                (TransactionTags tt) => tt.transactionId.equals(id),
              ))
          .get();
      for (final TransactionTag link in links) {
        await into(transactionTags).insert(
          TransactionTagsCompanion.insert(
            transactionId: newId,
            tagId: link.tagId,
          ),
          mode: InsertMode.insertOrIgnore,
        );
      }
      return (await byId(newId))!;
    });
  }

  Future<int> hardDelete(int id) {
    return (delete(transactions)..where((Transactions t) => t.id.equals(id)))
        .go();
  }

  Future<int> countAll({bool includeDeleted = false}) async {
    final countExp = transactions.id.count();
    final query = selectOnly(transactions)..addColumns([countExp]);
    if (!includeDeleted) {
      query.where(_notDeleted());
    }
    final TypedResult singleRow = await query.getSingle();
    return singleRow.read(countExp) ?? 0;
  }

  /// Saldo tiap rekening dalam SATU pass SQL (atomik):
  /// initial + income − expense − transfer_out + transfer_in.
  ///
  /// Index enum: 0=income, 1=expense, 2=transfer (lihat enums.dart).
  Future<Map<int, int>> balancesByAccount() {
    return customSelect(
      '''
      SELECT a.id AS account_id,
             a.initial_balance_minor AS initial_minor,
             IFNULL(SUM(CASE
               WHEN t.id IS NULL OR t.deleted_at IS NOT NULL THEN 0
               WHEN t.type = ? AND t.account_id = a.id THEN t.amount_minor
               WHEN t.type = ? AND t.account_id = a.id THEN -t.amount_minor
               WHEN t.type = ? AND t.to_account_id = a.id THEN t.amount_minor
               WHEN t.type = ? AND t.account_id = a.id THEN -t.amount_minor
               ELSE 0 END), 0) AS delta_minor
      FROM accounts a
      LEFT JOIN transactions t
        ON t.account_id = a.id OR t.to_account_id = a.id
      WHERE a.deleted_at IS NULL
      GROUP BY a.id
      ''',
      variables: [
        Variable.withInt(TransactionType.income.index),
        Variable.withInt(TransactionType.expense.index),
        Variable.withInt(TransactionType.transfer.index),
        Variable.withInt(TransactionType.transfer.index),
      ],
      readsFrom: {accounts, transactions},
    ).map((QueryRow row) {
      final int initial = row.read<int>('initial_minor');
      final int delta = row.read<int>('delta_minor');
      return MapEntry(row.read<int>('account_id'), initial + delta);
    }).get().then(Map<int, int>.fromEntries);
  }

  Future<void> setTagsForTransaction(int txId, List<Tag> tagList) {
    return transaction(() async {
      await (delete(transactionTags)
            ..where(
              (TransactionTags tt) => tt.transactionId.equals(txId),
            ))
          .go();
      for (final Tag tag in tagList) {
        await into(transactionTags).insert(
          TransactionTagsCompanion.insert(
            transactionId: txId,
            tagId: tag.id,
          ),
          mode: InsertMode.insertOrIgnore,
        );
      }
    });
  }

  /// Pola LIKE dengan escape % dan _ agar input user aman.
  static String likePattern(String raw) {
    final String escaped = raw
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
    return '%$escaped%';
  }

  /// Id transaksi yang cocok kata kunci: catatan, merchant, nama kategori,
  /// nama rekening, nama tag, atau nominal eksak bila query berupa angka.
  /// Semua pencarian dieksekusi di SQL (terindeks), bukan filter di UI.
  Future<Set<int>> searchIds(String rawQuery) async {
    final String q = rawQuery.trim();
    if (q.isEmpty) return <int>{};
    final String pattern = likePattern(q);

    Future<Set<int>> txIdsFrom(Expression<bool> Function(Transactions) where) {
      return (select(transactions)..where(where))
          .get()
          .then((List<Transaction> rows) =>
              rows.map((Transaction r) => r.id).toSet());
    }

    final Set<int> ids = await txIdsFrom(
      (Transactions t) => t.note.like(pattern) | t.merchant.like(pattern),
    );

    final List<int> catIds = await (select(categories)
          ..where((Categories c) => c.name.like(pattern)))
        .get()
        .then((List<Category> rows) => rows.map((Category c) => c.id).toList());
    if (catIds.isNotEmpty) {
      ids.addAll(await txIdsFrom(
        (Transactions t) => t.categoryId.isIn(catIds),
      ));
    }

    final List<int> accIds = await (select(accounts)
          ..where((Accounts a) => a.name.like(pattern)))
        .get()
        .then((List<Account> rows) => rows.map((Account a) => a.id).toList());
    if (accIds.isNotEmpty) {
      ids.addAll(await txIdsFrom(
        (Transactions t) =>
            t.accountId.isIn(accIds) | t.toAccountId.isIn(accIds),
      ));
    }

    final List<int> tagIds = await (select(tags)
          ..where((Tags t) => t.name.like(pattern)))
        .get()
        .then((List<Tag> rows) => rows.map((Tag t) => t.id).toList());
    if (tagIds.isNotEmpty) {
      final List<int> linked = await (select(transactionTags)
              ..where((TransactionTags tt) => tt.tagId.isIn(tagIds)))
          .get()
          .then((List<TransactionTag> rows) =>
              rows.map((TransactionTag l) => l.transactionId).toList());
      ids.addAll(linked);
    }

    final int? asNumber = int.tryParse(q);
    if (asNumber != null && asNumber > 0) {
      ids.addAll(await txIdsFrom(
        (Transactions t) => t.amountMinor.equals(asNumber),
      ));
    }
    return ids;
  }

  /// Bangun pernyataan terfilter BARU (statement drift tidak untuk dipakai
  /// ulang setelah dieksekusi).
  SimpleSelectStatement<Transactions, Transaction> _filteredStatement(
    HistoryFilter f,
  ) {
    final query = select(transactions)
      ..where((Transactions t) => t.deletedAt.isNull());

    final DateRange? range = f.range;
    if (range != null) {
      query.where(
        (Transactions t) =>
            t.date.isBiggerOrEqualValue(range.start) &
            t.date.isSmallerThanValue(range.end),
      );
    }
    final TransactionType? type = f.type;
    if (type != null) {
      query.where((Transactions t) => transactions.type.equalsValue(type));
    }
    final int? categoryId = f.categoryId;
    if (categoryId != null) {
      query.where((Transactions t) => t.categoryId.equals(categoryId));
    }
    final int? accountId = f.accountId;
    if (accountId != null) {
      query.where((Transactions t) =>
          t.accountId.equals(accountId) | t.toAccountId.equals(accountId));
    }
    final int? paymentMethodId = f.paymentMethodId;
    if (paymentMethodId != null) {
      query.where(
        (Transactions t) => t.paymentMethodId.equals(paymentMethodId),
      );
    }

    final OrderingMode mode =
        f.sortAscending ? OrderingMode.asc : OrderingMode.desc;
    if (f.sortField == HistorySortField.amount) {
      query.orderBy([
        (Transactions t) => OrderingTerm(expression: t.amountMinor, mode: mode),
        (Transactions t) => OrderingTerm(expression: t.date, mode: mode),
      ]);
    } else {
      query.orderBy([
        (Transactions t) => OrderingTerm(expression: t.date, mode: mode),
        (Transactions t) => OrderingTerm(expression: t.id, mode: mode),
      ]);
    }
    return query;
  }

  /// Daftar riwayat terfilter (sekali ambil).
  Future<List<TransactionWithRefs>> filteredList(HistoryFilter f) async {
    final String q = f.query.trim();
    if (q.isNotEmpty) {
      final Set<int> ids = await searchIds(q);
      if (ids.isEmpty) return const <TransactionWithRefs>[];
      final query = _filteredStatement(f)
        ..where((Transactions t) => t.id.isIn(ids));
      return _stitchRefs(await query.get());
    }
    return _stitchRefs(await _filteredStatement(f).get());
  }

  /// Versi reaktif [filteredList]. Pola BP-08: emisi pertama selalu hasil
  /// fetch langsung; refresh berikutnya dipicu tableUpdates.
  Stream<List<TransactionWithRefs>> watchFiltered(HistoryFilter f) async* {
    final AppDatabase db = attachedDatabase;
    final String q = f.query.trim();

    Future<List<TransactionWithRefs>> Function() runner = () async =>
        _stitchRefs(await _filteredStatement(f).get());
    if (q.isNotEmpty) {
      runner = () async {
        final Set<int> ids = await searchIds(q);
        if (ids.isEmpty) return const <TransactionWithRefs>[];
        final query = _filteredStatement(f)
          ..where((Transactions t) => t.id.isIn(ids));
        return _stitchRefs(await query.get());
      };
    }

    List<TransactionWithRefs> last = await runner();
    yield last;
    await for (final _ in db.tableUpdates(TableUpdateQuery.onAllTables({
      transactions,
      categories,
      accounts,
      tags,
      transactionTags,
    }))) {
      final List<TransactionWithRefs> next = await runner();
      final bool changed = next.length != last.length ||
          List<bool>.generate(
            next.length,
            (int i) =>
                next[i].transaction.id != last[i].transaction.id ||
                next[i].transaction.amountMinor !=
                    last[i].transaction.amountMinor,
          ).any((bool d) => d);
      if (changed) {
        last = next;
        yield next;
      }
    }
  }

  /// Deret bulanan income/expense untuk chart & perbandingan periode.
  /// [monthsBack] bulan TERAKHIR termasuk bulan berjalan relatif [now].
  Stream<List<MonthSeriesPoint>> watchMonthlySeries({
    required DateTime now,
    int monthsBack = 12,
  }) {
    assert(monthsBack > 0);
    final List<String> selects = <String>[];
    final List<Variable<Object>> variables = <Variable<Object>>[];
    final List<DateTime> starts = <DateTime>[];
    // Bangun dari bulan TERLAMA (j=0) ke bulan berjalan agar alias
    // selaras dengan posisi daftar bulan.
    for (int j = 0; j < monthsBack; j++) {
      final DateTime start =
          DateTime(now.year, now.month - (monthsBack - 1 - j));
      final DateTime end =
          DateTime(now.year, now.month - (monthsBack - 1 - j) + 1);
      starts.add(start);
      selects.add(
        'IFNULL(SUM(CASE WHEN type = ? AND date >= ? AND date < ? '
        'THEN amount_minor END), 0) AS income_$j',
      );
      variables
        ..add(Variable.withInt(TransactionType.income.index))
        ..add(Variable.withDateTime(start))
        ..add(Variable.withDateTime(end));
      selects.add(
        'IFNULL(SUM(CASE WHEN type = ? AND date >= ? AND date < ? '
        'THEN amount_minor END), 0) AS expense_$j',
      );
      variables
        ..add(Variable.withInt(TransactionType.expense.index))
        ..add(Variable.withDateTime(start))
        ..add(Variable.withDateTime(end));
    }

    return customSelect(
      'SELECT ${selects.join(', ')} FROM transactions '
      'WHERE deleted_at IS NULL AND source != ? AND date >= ?',
      variables: <Variable<Object>>[
        ...variables,
        // Setor/tarik dana goal dikecualikan — lihat dokumentasi di
        // `_totalsQuery` (alasan sama persis: bukan income/expense riil).
        // SEBELUMNYA method ini terlewat saat pengecualian ini
        // ditambahkan ke `_totalsQuery`/`watchFixedTotals`, jadi tren 12
        // bulan, perbandingan bulan, dan proyeksi net di halaman Analisis
        // sempat ikut menghitung transaksi Tujuan Tabungan sebagai
        // pemasukan/pengeluaran asli.
        Variable.withInt(TxnSource.goalContribution.index),
        Variable.withDateTime(starts.first),
      ],
      readsFrom: {transactions},
    ).watchSingle().map((QueryRow row) => <MonthSeriesPoint>[
          for (int i = 0; i < monthsBack; i++)
            MonthSeriesPoint(
              monthStart: starts[i],
              incomeMinor: row.read<int>('income_$i'),
              expenseMinor: row.read<int>('expense_$i'),
            ),
        ]);
  }
  Future<List<Tag>> tagsForTransaction(int txId) async {
    final List<TransactionTag> links = await (select(transactionTags)
            ..where((TransactionTags tt) => tt.transactionId.equals(txId)))
        .get();
    if (links.isEmpty) return const <Tag>[];
    final List<int> ids = links.map((TransactionTag l) => l.tagId).toList();
    return (select(tags)..where((Tags t) => t.id.isIn(ids))).get();
  }

  /// Total income/expense untuk 4 periode tetap (hari/minggu/bulan/tahun)
  /// dalam SATU pass SQL — dipakai kartu "Ringkasan Cepat" dashboard.
  ///
  /// Index enum: 0=income, 1=expense, 2=transfer.
  Stream<Map<String, int>> watchFixedTotals() {
    final DateTime now = DateTime.now();
    final DateTime dayStart = startOfToday(now);
    final DateTime weekStart = startOfWeekMonday(now);
    final DateTime monthStart = DateTime(now.year, now.month);
    final DateTime yearStart = DateTime(now.year);

    return customSelect(
      '''
      SELECT
        IFNULL(SUM(CASE WHEN type = ? AND date >= ? THEN amount_minor END), 0) AS day_income,
        IFNULL(SUM(CASE WHEN type = ? AND date >= ? THEN amount_minor END), 0) AS day_expense,
        IFNULL(SUM(CASE WHEN type = ? AND date >= ? THEN amount_minor END), 0) AS week_income,
        IFNULL(SUM(CASE WHEN type = ? AND date >= ? THEN amount_minor END), 0) AS week_expense,
        IFNULL(SUM(CASE WHEN type = ? AND date >= ? THEN amount_minor END), 0) AS month_income,
        IFNULL(SUM(CASE WHEN type = ? AND date >= ? THEN amount_minor END), 0) AS month_expense,
        IFNULL(SUM(CASE WHEN type = ? AND date >= ? THEN amount_minor END), 0) AS year_income,
        IFNULL(SUM(CASE WHEN type = ? AND date >= ? THEN amount_minor END), 0) AS year_expense
      FROM transactions
      WHERE deleted_at IS NULL AND source != ? AND date >= ?
      ''',
      variables: [
        Variable.withInt(TransactionType.income.index),
        Variable.withDateTime(dayStart),
        Variable.withInt(TransactionType.expense.index),
        Variable.withDateTime(dayStart),
        Variable.withInt(TransactionType.income.index),
        Variable.withDateTime(weekStart),
        Variable.withInt(TransactionType.expense.index),
        Variable.withDateTime(weekStart),
        Variable.withInt(TransactionType.income.index),
        Variable.withDateTime(monthStart),
        Variable.withInt(TransactionType.expense.index),
        Variable.withDateTime(monthStart),
        Variable.withInt(TransactionType.income.index),
        Variable.withDateTime(yearStart),
        Variable.withInt(TransactionType.expense.index),
        Variable.withDateTime(yearStart),
        // Setor/tarik dana goal dikecualikan — lihat dokumentasi
        // di `_totalsQuery` (alasan sama persis).
        Variable.withInt(TxnSource.goalContribution.index),
        Variable.withDateTime(yearStart),
      ],
      readsFrom: {transactions},
    ).watchSingle().map((QueryRow row) => <String, int>{
          'day_income': row.read<int>('day_income'),
          'day_expense': row.read<int>('day_expense'),
          'week_income': row.read<int>('week_income'),
          'week_expense': row.read<int>('week_expense'),
          'month_income': row.read<int>('month_income'),
          'month_expense': row.read<int>('month_expense'),
          'year_income': row.read<int>('year_income'),
          'year_expense': row.read<int>('year_expense'),
        });
  }

  static DateTime startOfToday(DateTime now) =>
      DateTime(now.year, now.month, now.day);

  static DateTime startOfWeekMonday(DateTime now) {
    final DateTime today = DateTime(now.year, now.month, now.day);
    return today.subtract(Duration(days: today.weekday - DateTime.monday));
  }
}
