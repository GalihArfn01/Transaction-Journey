import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/security/app_lock_controller.dart';
import '../../data/datasource/database_provider.dart';
import '../../data/repository/security_repository.dart';

/// Repository keamanan — satu instance, policy-nya dipakai bersama
/// controller gerbang agar timeout dari settings selalu sinkron.
final Provider<SecurityRepository> securityRepositoryProvider =
    Provider<SecurityRepository>((Ref ref) {
  final SecurityRepository repo = SecurityRepository(
    ref.watch(appDatabaseProvider),
  );
  return repo;
});

/// Controller gerbang auto-lock. Timeout dimuat dari settings saat
/// pertama dibutuhkan oleh pemakai (dipanggil wiring AppShell saat startup).
final Provider<AppLockController> appLockControllerProvider =
    Provider<AppLockController>((Ref ref) {
  final SecurityRepository repo = ref.watch(securityRepositoryProvider);
  return AppLockController(
    autoLockPolicy: repo.autoLockPolicy,
    loadHasPin: repo.hasPin,
  );
});
