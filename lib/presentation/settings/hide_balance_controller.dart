import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform/widget_bridge.dart';
import '../../core/utils/balance_privacy.dart';
import '../../data/datasource/app_database.dart';
import '../../data/datasource/database_provider.dart';

/// Apakah total saldo disembunyikan (dashboard + widget). Tersimpan di
/// tabel `settings` sehingga bertahan antar-sesi dan ikut backup.
final StreamProvider<bool> hideBalanceProvider = StreamProvider<bool>(
  (Ref ref) => ref
      .watch(appDatabaseProvider)
      .settingsDao
      .watchValue(kHideBalanceSettingKey)
      .map(parseHideBalance),
);

/// Simpan pilihan lalu segarkan widget layar utama agar ikut
/// menyembunyikan/menampilkan saldo.
Future<void> setHideBalance(AppDatabase db, bool hide) async {
  await db.settingsDao.setValue(kHideBalanceSettingKey, hide ? '1' : '0');
  WidgetBridge.notifyDataChanged(db);
}
