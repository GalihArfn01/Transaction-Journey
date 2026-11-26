import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasource/app_database.dart';
import '../../data/datasource/database_provider.dart';
import '../../data/repository/category_repository.dart';

/// Filter daftar kategori pada halaman manajemen kategori.
enum CategoryListFilter { all, income, expense }

/// Provider repository kategori — satu instance, ditutup bersama DB.
final Provider<CategoryRepository> categoryRepositoryProvider =
    Provider<CategoryRepository>(
  (Ref ref) => CategoryRepository(ref.watch(appDatabaseProvider)),
);

/// Semua kategori (aktif + nonaktif, tanpa yang dihapus) untuk halaman
/// manajemen. Untuk pemilih form gunakan activeCategoriesProvider.
final StreamProvider<List<Category>> allCategoriesProvider =
    StreamProvider<List<Category>>(
  (Ref ref) => ref.watch(appDatabaseProvider).categoryDao.watchAll(),
);

/// Filter seksi yang tampil pada halaman daftar kategori.
final StateProvider<CategoryListFilter> categoryListFilterProvider =
    StateProvider<CategoryListFilter>(
  (Ref ref) => CategoryListFilter.all,
);
