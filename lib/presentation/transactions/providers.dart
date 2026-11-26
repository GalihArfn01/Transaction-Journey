import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasource/app_database.dart';
import '../../data/datasource/database_provider.dart';
import '../../data/datasource/dao/transaction_dao.dart';
import '../../data/repository/transaction_repository.dart';
import '../../domain/model/enums.dart';

/// Provider repository — satu instance, ditutup bersama DB.
final Provider<TransactionRepository> transactionRepositoryProvider =
    Provider<TransactionRepository>(
  (Ref ref) => TransactionRepository(ref.watch(appDatabaseProvider)),
);

/// Referensi form: rekening aktif.
final StreamProvider<List<Account>> activeAccountsProvider =
    StreamProvider<List<Account>>(
  (Ref ref) => ref.watch(appDatabaseProvider).accountDao.watchActive(),
);

/// Referensi form: kategori aktif per jenis.
final StreamProviderFamily<List<Category>, TransactionType>
    activeCategoriesProvider =
    StreamProvider.family<List<Category>, TransactionType>(
  (Ref ref, TransactionType type) =>
      ref.watch(appDatabaseProvider).categoryDao.watchActive(type),
);

/// Referensi form: metode pembayaran aktif.
final StreamProvider<List<PaymentMethod>> activePaymentMethodsProvider =
    StreamProvider<List<PaymentMethod>>(
  (Ref ref) => ref.watch(appDatabaseProvider).paymentMethodDao.watchActive(),
);

/// Daftar transaksi terbaru (detail) untuk halaman riwayat sederhana.
final StreamProvider<List<TransactionWithRefs>> recentTransactionsProvider =
    StreamProvider<List<TransactionWithRefs>>(
  (Ref ref) => ref.watch(appDatabaseProvider).transactionDao.watchDetailed(),
);
