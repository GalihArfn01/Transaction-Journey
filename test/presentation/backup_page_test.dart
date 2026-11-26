import 'package:drift/drift.dart' show QueryRow;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transaction_journey/app/app_theme.dart';
import 'package:transaction_journey/data/datasource/app_database.dart';
import 'package:transaction_journey/data/datasource/tables.dart';
import 'package:transaction_journey/data/datasource/database_provider.dart';
import 'package:transaction_journey/data/repository/backup_crypto.dart';
import 'package:transaction_journey/data/repository/backup_repository.dart';
import 'package:transaction_journey/domain/model/enums.dart';
import 'package:transaction_journey/presentation/backup/backup_page.dart';

/// Transisi halaman tanpa animasi untuk test - Zoom default Flutter 3.27
/// membungkus konten rute dengan Offstage (snapshot) yang tidak kunjung
/// lepas di FakeAsync binding sehingga finder gagal.
class _NoTransitionBuilder extends PageTransitionsBuilder {
  const _NoTransitionBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      child;
}

/// SnackBar memakai Timer auto-dismiss (4s); widget test melarang
/// timer tersisa -> majukan waktu setelah aksi yang menampilkan snackbar.
Future<void> flushSnackbars(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 4));
  await tester.pumpAndSettle();
}

/// Permukaan tinggi — halaman Backup kini memuat 3 kartu (Buat Backup +
/// Backup Otomatis + Pulihkan) sehingga tombol bisa berada DI BAWAH
/// viewport default 800x600. Tap tanpa `ensureVisible` hanya "berhasil"
/// karena tidak kena hit-test (BP-02).
Future<void> useTallSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(600, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

/// Ketuk setelahEnsure widget masuk viewport (aman dari silent miss).
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(finder);
}

void main() {
  late AppDatabase db;
  late BackupRepository repo;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = BackupRepository(db);
  });

  tearDown(() => db.close());

  Future<int> accountCount() async {
    final QueryRow row = await db
        .customSelect('SELECT COUNT(*) AS n FROM accounts')
        .getSingle();
    return row.read<int>('n');
  }

  Widget wrap(Widget child) => ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: AppTheme.light().copyWith(
            pageTransitionsTheme: const PageTransitionsTheme(
              builders: <TargetPlatform, PageTransitionsBuilder>{
                TargetPlatform.android: _NoTransitionBuilder(),
                TargetPlatform.iOS: _NoTransitionBuilder(),
                TargetPlatform.macOS: _NoTransitionBuilder(),
                TargetPlatform.windows: _NoTransitionBuilder(),
                TargetPlatform.linux: _NoTransitionBuilder(),
              },
            ),
          ),
          locale: const Locale('id'),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('id'), Locale('en')],
          home: child,
        ),
      );

  testWidgets('tombol Buat Backup & Pulihkan tampil', (WidgetTester tester) async {
    await useTallSurface(tester);
    await tester.pumpWidget(wrap(const BackupPage()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('backup_create_button')), findsOneWidget);
    expect(find.byKey(const Key('backup_restore_button')), findsOneWidget);
    expect(find.byKey(const Key('backup_auto_switch')), findsOneWidget);
    expect(find.text('Backup & Restore'), findsOneWidget);

    await db.close();
    await tester.pumpAndSettle();
  });

  testWidgets('pratinjau muncul; Batal tidak mengubah DB',
      (WidgetTester tester) async {
    await useTallSurface(tester);
    // Fixture dari kondisi DB saat ini.
    final String fixture =
        repo.encodeBackup(await repo.collectBackup());
    final int countBefore = await accountCount();

    await tester.pumpWidget(wrap(BackupPage(
      pickBackupContents: () async => fixture, // tanpa file_picker sungguhan
    )));
    await tester.pumpAndSettle();

    await tapVisible(tester, find.byKey(const Key('backup_restore_button')));
    await tester.pumpAndSettle();

    // Dialog konfirmasi dengan pratinjau jumlah baris per tabel.
    expect(find.byKey(const Key('backup_confirm_dialog')), findsOneWidget);
    expect(find.textContaining('accounts:'), findsWidgets);
    expect(find.textContaining('categories:'), findsWidgets);
    expect(find.byKey(const Key('backup_confirm_button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('backup_cancel_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('backup_confirm_dialog')), findsNothing);
    expect(await accountCount(), countBefore);

    await db.close();
    await tester.pumpAndSettle();
  });

  testWidgets('backup otomatis: toggle + interval tersimpan di settings',
      (WidgetTester tester) async {
    await useTallSurface(tester);
    await tester.pumpWidget(wrap(const BackupPage()));
    await tester.pumpAndSettle();

    // Default: mati, dropdown jadwal tersembunyi.
    final SwitchListTile autoSwitch =
        tester.widget(find.byKey(const Key('backup_auto_switch')));
    expect(autoSwitch.value, isFalse);
    expect(
      find.byKey(const Key('backup_auto_interval')),
      findsNothing,
    );
    expect(find.text('Belum pernah dibuat otomatis.'), findsOneWidget);

    // Nyalakan: dropdown muncul + interval default Mingguan tersimpan.
    // (Salinan pertama otomatis gagal di test — path_provider tak ada —
    // tapi itu justru bukti kegagalannya dilaporkan, bukan diam.)
    await tapVisible(tester, find.byKey(const Key('backup_auto_switch')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('backup_auto_interval')), findsOneWidget);

    // Pengaturan tersimpan meski proses backup pertama mungkin masih
    // berjalan — tunggu dengan pump berbatas (pola BP-13).
    AutoBackupSettings saved = await repo.readAutoBackupSettings();
    for (int i = 0; i < 30 && !saved.enabled; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      saved = await repo.readAutoBackupSettings();
    }
    expect(saved.enabled, isTrue);
    expect(saved.intervalDays, kDefaultAutoBackupIntervalDays);

    // Ganti interval -> tersimpan. Nilai dipanggil lewat callback
    // widget (bukan mengetuk item menu) supaya tidak bergantung pada
    // geometri overlay dropdown yang fragile di widget-test.
    //
    // Tunggu sampai dropdown benar-benar SIAP (onChanged non-null):
    // setelah toggle, halaman masih `busy` sampai penyimpanan settings +
    // percobaan backup otomatis pertama selesai — beberapa langkah async
    // yang belum tentu selesai oleh satu `pumpAndSettle` (pending timer
    // tidak membuat frame baru terjadwal).
    DropdownButtonFormField<int>? dropdown;
    for (int i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      final Finder finder = find.byKey(const Key('backup_auto_interval'));
      if (finder.evaluate().isEmpty) continue;
      final DropdownButtonFormField<int> candidate =
          tester.widget(finder);
      if (candidate.onChanged != null) {
        dropdown = candidate;
        break;
      }
    }
    expect(
      dropdown,
      isNotNull,
      reason: 'dropdown jadwal harus siap dipakai setelah toggle',
    );
    expect(find.text('Mingguan'), findsOneWidget);
    dropdown!.onChanged!(30);
    await tester.pumpAndSettle();
    saved = await repo.readAutoBackupSettings();
    expect(saved.intervalDays, 30);

    await flushSnackbars(tester);
    await db.close();
    await tester.pumpAndSettle();
  });

  testWidgets('enkripsi: passphrase tidak sama ditolak sebelum menyentuh IO',
      (WidgetTester tester) async {
    await useTallSurface(tester);
    await tester.pumpWidget(wrap(const BackupPage()));
    await tester.pumpAndSettle();

    await tapVisible(tester, find.byKey(const Key('backup_encrypt_switch')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('backup_passphrase_field')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const Key('backup_passphrase_field')),
      'kalimat rahasia qa',
    );
    await tester.enterText(
      find.byKey(const Key('backup_passphrase_confirm_field')),
      'kalimat yang beda',
    );
    await tapVisible(tester, find.byKey(const Key('backup_create_button')));
    await tester.pumpAndSettle();

    expect(find.text('Ulangi passphrase tidak sama'), findsOneWidget);
    await flushSnackbars(tester);

    await db.close();
    await tester.pumpAndSettle();
  });

  testWidgets('restore terenkripsi: salah -> error, benar -> pulih',
      (WidgetTester tester) async {
    await useTallSurface(tester);
    const String pass = 'kalimat rahasia qa';
    final String plain = repo.encodeBackup(await repo.collectBackup());
    // Payload "terenkripsi" palsu: yang diuji di sini ALUR DIALOG, bukan
    // kripto (PBKDF2 nyata tidak pernah selesai di FakeAsync — lihat
    // catatan decryptBackupContents di BackupPage dan test kripto terpisah
    // di test/data/backup_crypto_test.dart).
    const String fakePayload = 'ZmFrZS1wYXlsb2FkLXVudWstdGVzdA==';
    const String fakeEncrypted = '$kEncryptedBackupPrefix$fakePayload';
    expect(isEncryptedBackup(fakeEncrypted), isTrue);

    await tester.pumpWidget(wrap(BackupPage(
      pickBackupContents: () async => fakeEncrypted,
      decryptBackupContents: (String contents, String passphrase) async {
        if (passphrase != pass) {
          throw BackupValidationError(
            'Passphrase salah atau file backup rusak',
          );
        }
        return plain;
      },
    )));
    await tester.pumpAndSettle();

    // Passphrase salah -> dialog passphrase + snackbar error.
    await tapVisible(tester, find.byKey(const Key('backup_restore_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('backup_passphrase_dialog')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('backup_restore_passphrase_field')),
      'jawaban yang keliru',
    );
    await tester.tap(
      find.byKey(const Key('backup_restore_passphrase_submit')),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Passphrase salah'), findsOneWidget);
    await flushSnackbars(tester);

    // Passphrase benar -> pratinjau -> konfirmasi -> pulih.
    await tapVisible(tester, find.byKey(const Key('backup_restore_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('backup_passphrase_dialog')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('backup_restore_passphrase_field')),
      pass,
    );
    await tester.tap(
      find.byKey(const Key('backup_restore_passphrase_submit')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('backup_confirm_dialog')), findsOneWidget);
    await tester.tap(find.byKey(const Key('backup_confirm_button')));
    await tester.pumpAndSettle();
    expect(find.text('Pemulihan selesai'), findsOneWidget);
    await flushSnackbars(tester);

    await db.close();
    await tester.pumpAndSettle();
  });

  testWidgets('konfirmasi Pulihkan mengganti isi DB sesuai backup',
      (WidgetTester tester) async {
    await useTallSurface(tester);
    // 1) Buat rekening ekstra lalu ambil snapshot backup-nya.
    await db.accountDao.insertAccount(
      AccountsCompanion.insert(name: 'EkstraQA', type: AccountType.cash),
    );
    final String fixture =
        repo.encodeBackup(await repo.collectBackup());

    // 2) Hapus rekening ekstra -> DB kini BERBEDA dari fixture.
    await db.customStatement('DELETE FROM accounts WHERE name = \'EkstraQA\'');
    final int countWithoutExtra = await accountCount();
    expect(countWithoutExtra, lessThan(repo.preview(fixture).counts['accounts']!));

    // 3) Pulihkan via UI (file di-inject).
    await tester.pumpWidget(wrap(BackupPage(
      pickBackupContents: () async => fixture,
    )));
    await tester.pumpAndSettle();

    await tapVisible(tester, find.byKey(const Key('backup_restore_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('backup_confirm_button')));
    await tester.pumpAndSettle();

    // Snackbar sukses tampil (BP-13: jangan asal settle, cek marker).
    expect(find.text('Pemulihan selesai'), findsOneWidget);
    await flushSnackbars(tester);

    // Isi DB kembali persis seperti saat backup dibuat.
    expect(await accountCount(), greaterThan(countWithoutExtra));
    final List<Account> restored = await (db.select(db.accounts)
          ..where((Accounts a) => a.name.equals('EkstraQA')))
        .get();
    expect(restored, hasLength(1));

    await db.close();
    await tester.pumpAndSettle();
  });
}
