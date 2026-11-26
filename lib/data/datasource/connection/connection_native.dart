import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' show Database;

/// Implementasi koneksi untuk platform native (Android/iOS/desktop).
/// Tidak boleh di-import langsung dari kode lain — gunakan connection.dart.
///
/// PENTING (bug widget layar utama): file SQLite yang sama bisa dibuka
/// dari DUA isolate/engine Flutter BERBEDA secara bersamaan — engine
/// utama (foreground, dibuka dari `main()`) dan engine headless yang
/// di-spawn native `WidgetHeadlessExecutor.kt` setiap kali tombol +/-
/// widget "Saldo" ditekan (lihat dokumentasi di sana; ia SELALU memakai
/// jalur headless, bahkan saat aplikasi utama sedang berjalan). Tanpa
/// `journal_mode=WAL` + `busy_timeout`, mode jurnal default SQLite
/// ("delete") membuat kedua koneksi saling kunci: begitu satu menulis,
/// koneksi lain yang kebetulan mencoba baca/tulis di saat bersamaan
/// langsung gagal dengan "database is locked" alih-alih menunggu —
/// dan karena tidak ada percobaan ulang, mutasi dari widget (adjustBalance)
/// bisa senyap gagal tanpa bekas (tombol widget terasa "tidak berfungsi").
/// WAL mengizinkan satu penulis + banyak pembaca berjalan bersamaan tanpa
/// saling blokir, dan `busy_timeout` membuat sisa kontensi (mis. dua
/// penulis persis bersamaan) menunggu sampai 5 detik alih-alih langsung
/// melempar error.
QueryExecutor openAppDatabaseConnection() {
  return LazyDatabase(() async {
    final Directory dir = await getApplicationDocumentsDirectory();
    final File file = File(p.join(dir.path, 'transaction_journey.sqlite'));
    // Query dijalankan di background isolate agar UI tidak terblokir I/O.
    return NativeDatabase.createInBackground(
      file,
      setup: (Database db) {
        db.execute('PRAGMA journal_mode=WAL;');
        db.execute('PRAGMA busy_timeout=5000;');
      },
    );
  });
}
