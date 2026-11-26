import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables.dart';

part 'settings_dao.g.dart';

@DriftAccessor(tables: [Settings])
class SettingsDao extends DatabaseAccessor<AppDatabase>
    with _$SettingsDaoMixin {
  SettingsDao(super.db);

  Future<String?> getValue(String key) async {
    final Setting? row = await (select(settings)
          ..where((Settings s) => s.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Stream<String?> watchValue(String key) {
    return (select(settings)..where((Settings s) => s.key.equals(key)))
        .watchSingleOrNull()
        .map((Setting? row) => row?.value);
  }

  /// Upsert — aman dipanggil berulang.
  Future<void> setValue(String key, String value) {
    return into(settings).insertOnConflictUpdate(
      SettingsCompanion.insert(key: key, value: value),
    );
  }

  Future<void> remove(String key) {
    return (delete(settings)..where((Settings s) => s.key.equals(key))).go();
  }
}
