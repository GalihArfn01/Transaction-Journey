import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables.dart';

part 'payment_method_dao.g.dart';

@DriftAccessor(tables: [PaymentMethods])
class PaymentMethodDao extends DatabaseAccessor<AppDatabase>
    with _$PaymentMethodDaoMixin {
  PaymentMethodDao(super.db);

  Stream<List<PaymentMethod>> watchActive() {
    return (select(paymentMethods)
          ..where((PaymentMethods p) => p.isActive.equals(true))
          ..orderBy([(PaymentMethods p) => OrderingTerm.asc(p.id)]))
        .watch();
  }

  Future<List<PaymentMethod>> allActive() {
    return (select(paymentMethods)
          ..where((PaymentMethods p) => p.isActive.equals(true)))
        .get();
  }

  Future<PaymentMethod?> byId(int id) {
    return (select(paymentMethods)
          ..where((PaymentMethods p) => p.id.equals(id)))
        .getSingleOrNull();
  }

  Future<int> insertMethod(PaymentMethodsCompanion entry) =>
      into(paymentMethods).insert(entry);

  Future<int> setActive(int id, bool active) {
    return (update(paymentMethods)..where((PaymentMethods p) => p.id.equals(id)))
        .write(PaymentMethodsCompanion(isActive: Value(active)));
  }
}
