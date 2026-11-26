import 'package:drift/drift.dart';

/// Stub web: produk utama adalah Android/iOS. Build web hanya untuk
/// verifikasi kompilasi — runtime web membutuhkan WasmDatabase + asset
/// sqlite3.wasm (bisa diaktifkan nanti bila diperlukan).
QueryExecutor openAppDatabaseConnection() {
  throw UnsupportedError('Platform web belum didukung');
}
