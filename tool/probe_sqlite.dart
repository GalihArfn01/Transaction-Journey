import 'package:sqlite3/sqlite3.dart';

void main() {
  try {
    final Database db = sqlite3.openInMemory();
    final ResultSet result = db.select('SELECT 1 AS one');
    print('SQLITE_OK version=${sqlite3.version.libVersion} probe=${result.first['one']}');
    db.dispose();
  } catch (e) {
    print('SQLITE_FAIL: $e');
  }
}
