import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables.dart';

part 'tag_dao.g.dart';

@DriftAccessor(tables: [Tags])
class TagDao extends DatabaseAccessor<AppDatabase> with _$TagDaoMixin {
  TagDao(super.db);

  Stream<List<Tag>> watchAll() {
    return (select(tags)..orderBy([(Tags t) => OrderingTerm.asc(t.name)]))
        .watch();
  }

  /// Ambil tag berdasarkan nama; buat bila belum ada (case-insensitive).
  Future<Tag> ensureTag(String name) async {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Nama tag tidak boleh kosong');
    }
    final Tag? existing = await (select(tags)
          ..where((Tags t) => t.name.lower().equals(trimmed.toLowerCase())))
        .getSingleOrNull();
    if (existing != null) return existing;
    final int id = await into(tags).insert(
      TagsCompanion.insert(name: trimmed),
      mode: InsertMode.insertOrIgnore,
    );
    if (id != 0) {
      return Tag(id: id, name: trimmed);
    }
    // Race: baris sudah dibuat proses lain — ambil ulang.
    final Tag? raced = await (select(tags)
          ..where((Tags t) => t.name.lower().equals(trimmed.toLowerCase())))
        .getSingleOrNull();
    if (raced == null) {
      throw StateError('Gagal membuat tag "$trimmed"');
    }
    return raced;
  }

  Future<Tag?> byId(int id) {
    return (select(tags)..where((Tags t) => t.id.equals(id)))
        .getSingleOrNull();
  }
}
