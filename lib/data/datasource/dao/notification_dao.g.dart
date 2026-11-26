// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'notification_dao.dart';

// ignore_for_file: type=lint
mixin _$NotificationSourceDaoMixin on DatabaseAccessor<AppDatabase> {
  $NotificationSourcesTable get notificationSources =>
      attachedDatabase.notificationSources;
}
mixin _$NotificationEventDaoMixin on DatabaseAccessor<AppDatabase> {
  $NotificationSourcesTable get notificationSources =>
      attachedDatabase.notificationSources;
  $CategoriesTable get categories => attachedDatabase.categories;
  $AccountsTable get accounts => attachedDatabase.accounts;
  $PaymentMethodsTable get paymentMethods => attachedDatabase.paymentMethods;
  $FinancialGoalsTable get financialGoals => attachedDatabase.financialGoals;
  $TransactionsTable get transactions => attachedDatabase.transactions;
  $NotificationEventsTable get notificationEvents =>
      attachedDatabase.notificationEvents;
}
