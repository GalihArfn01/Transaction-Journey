// Pemilih koneksi database per-platform via conditional export:
// dart.library.io -> native (Android/iOS/desktop, sqlite3 FFI);
// selain itu -> stub web.
export 'connection_native.dart' if (dart.library.js_interop) 'connection_web.dart';
