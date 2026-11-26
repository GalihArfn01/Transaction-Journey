import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables.dart';

part 'rule_dao.g.dart';

@DriftAccessor(tables: [MerchantCategoryRules])
class RuleDao extends DatabaseAccessor<AppDatabase> with _$RuleDaoMixin {
  RuleDao(super.db);

  /// Aturan aktif terurut prioritas — urutan ini adalah urutan evaluasi
  /// smart categorization (pertama cocok = menang, didukung hitCount).
  Stream<List<MerchantCategoryRule>> watchEnabled() {
    return (select(merchantCategoryRules)
          ..where((MerchantCategoryRules r) => r.enabled.equals(true))
          ..orderBy([
            (MerchantCategoryRules r) => OrderingTerm.desc(r.priority),
            (MerchantCategoryRules r) => OrderingTerm.desc(r.hitCount),
            (MerchantCategoryRules r) => OrderingTerm.desc(r.id),
          ]))
        .watch();
  }

  Stream<List<MerchantCategoryRule>> watchAll() {
    return (select(merchantCategoryRules)
          ..orderBy([
            (MerchantCategoryRules r) => OrderingTerm.desc(r.priority),
            (MerchantCategoryRules r) => OrderingTerm.desc(r.id),
          ]))
        .watch();
  }

  Future<List<MerchantCategoryRule>> enabledRules() {
    return (select(merchantCategoryRules)
          ..where((MerchantCategoryRules r) => r.enabled.equals(true)))
        .get();
  }

  Future<MerchantCategoryRule?> byId(int id) {
    return (select(merchantCategoryRules)
          ..where((MerchantCategoryRules r) => r.id.equals(id)))
        .getSingleOrNull();
  }

  Future<int> insertRule(MerchantCategoryRulesCompanion entry) =>
      into(merchantCategoryRules).insert(entry);

  Future<int> updateRule(int id, MerchantCategoryRulesCompanion entry) {
    return (update(merchantCategoryRules)
          ..where((MerchantCategoryRules r) => r.id.equals(id)))
        .write(entry);
  }

  /// Hard delete sengaja: aturan murah dibuat ulang dan tidak memiliki
  /// dependensi transaksional.
  Future<int> deleteRule(int id) {
    return (delete(merchantCategoryRules)
          ..where((MerchantCategoryRules r) => r.id.equals(id)))
        .go();
  }

  Future<void> incrementHit(int id) {
    return customUpdate(
      'UPDATE merchant_category_rules SET hit_count = hit_count + 1 WHERE id = ?',
      variables: [Variable.withInt(id)],
      updates: {merchantCategoryRules},
    );
  }
}
