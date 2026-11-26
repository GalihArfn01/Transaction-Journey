import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_database.dart';
import 'connection/connection.dart';

/// Provider database global.
///
/// Unit test TIDAK memakai provider ini — mereka membangun
/// `AppDatabase(NativeDatabase.memory())` langsung agar deterministik.
final Provider<AppDatabase> appDatabaseProvider = Provider<AppDatabase>((
  Ref ref,
) {
  final AppDatabase db = AppDatabase(openAppDatabaseConnection());
  ref.onDispose(db.close);
  return db;
});
