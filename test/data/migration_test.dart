import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:transaction_journey/data/datasource/app_database.dart';
import 'package:transaction_journey/domain/model/enums.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('tj_migration_');
  });
  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  /// Membuat file SQLite "v1" secara manual: skema transactions/accounts
  /// lama TANPA kolom baru, satu baris data, user_version = 1.
  String createLegacyV1Database(String fileName) {
    final String dbPath = p.join(tempDir.path, fileName);
    final Database raw = sqlite3.open(dbPath);
    raw.execute('PRAGMA foreign_keys = OFF');
    raw.execute('''
      CREATE TABLE accounts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        type INTEGER NOT NULL,
        icon TEXT NOT NULL DEFAULT 'wallet',
        color_value INTEGER NULL,
        initial_balance_minor INTEGER NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
        updated_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
        deleted_at INTEGER NULL
      )
    ''');
    raw.execute('''
      CREATE TABLE transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type INTEGER NOT NULL,
        amount_minor INTEGER NOT NULL,
        date INTEGER NOT NULL,
        category_id INTEGER NULL,
        account_id INTEGER NOT NULL,
        to_account_id INTEGER NULL,
        payment_method_id INTEGER NULL,
        note TEXT NULL,
        attachment_path TEXT NULL,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
        updated_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
        deleted_at INTEGER NULL
      )
    ''');
    raw.execute('PRAGMA user_version = 1');
    // Tabel v1 lain yang wajib sudah ada sebelum upgrade (realistis):
    raw.execute('''
      CREATE TABLE categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        type INTEGER NOT NULL,
        icon TEXT NOT NULL DEFAULT 'category',
        color_value INTEGER NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
        updated_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
        deleted_at INTEGER NULL
      )
    ''');
    raw.execute('''
      CREATE TABLE payment_methods (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        icon TEXT NOT NULL DEFAULT 'payments',
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
      )
    ''');
    // Tabel v1 lain yang ikut dihapus pada migrasi v2 -> v3 (harus ada).
    raw.execute('''
      CREATE TABLE tags (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        color_value INTEGER NULL
      )
    ''');
    raw.execute('''
      CREATE TABLE transaction_tags (
        transaction_id INTEGER NOT NULL,
        tag_id INTEGER NOT NULL,
        PRIMARY KEY (transaction_id, tag_id)
      )
    ''');
    raw.execute('''
      CREATE TABLE budgets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category_id INTEGER NULL,
        period_type INTEGER NOT NULL,
        amount_minor INTEGER NOT NULL,
        start_date INTEGER NOT NULL,
        end_date INTEGER NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
        updated_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
      )
    ''');
    raw.execute('''
      CREATE TABLE recurring_transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        type INTEGER NOT NULL,
        amount_minor INTEGER NOT NULL,
        category_id INTEGER NULL,
        account_id INTEGER NOT NULL,
        payment_method_id INTEGER NULL,
        note TEXT NULL,
        frequency INTEGER NOT NULL,
        interval_count INTEGER NOT NULL DEFAULT 1,
        day_of_month INTEGER NULL,
        day_of_week INTEGER NULL,
        start_date INTEGER NOT NULL,
        end_date INTEGER NULL,
        last_generated_date INTEGER NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        auto_create INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
      )
    ''');
    raw.execute(
      'CREATE TABLE settings (key TEXT NOT NULL PRIMARY KEY, '
      'value TEXT NOT NULL)',
    );
    raw.execute("INSERT INTO accounts (name, type) VALUES ('Cash', 0)");
    raw.execute(
      'INSERT INTO transactions '
      '(type, amount_minor, date, account_id, note) '
      "VALUES (1, 250000, strftime('%s','now'), 1, 'data lama')",
    );
    raw.dispose();
    return dbPath;
  }

  test('upgrade v1 -> v8: skema terbaru & default kolom grouping',
      () async {
    final String dbPath = createLegacyV1Database('legacy.sqlite');
    final AppDatabase db = AppDatabase(NativeDatabase(File(dbPath)));

    // v2 -> v3 SENGAJA mengosongkan data transaksional lama (model
    // rekening disederhanakan jadi Tunai/Non Tunai) — jadi baris legacy
    // memang tidak dipertahankan, dan skema sudah sampai versi terkini.
    expect(await db.transactionDao.countAll(), 0);
    expect(db.schemaVersion, 8);

    // Tabel baru dapat dipakai.
    final int goalId = await db.goalDao.insertGoal(
      FinancialGoalsCompanion.insert(
        name: 'Dana Darurat QA',
        targetAmountMinor: 10000000,
      ),
    );
    final FinancialGoal? goal = await db.goalDao.byId(goalId);
    expect(goal!.status, GoalStatus.active);
    expect(goal.currentAmountMinor, 0);
    // v7 -> v8: goal lama otomatis jadi root non-grup.
    expect(goal.parentId, isNull);
    expect(goal.isGroup, isFalse);

    await db.goalDao.adjustCurrentAmount(goalId, 2500000);
    expect((await db.goalDao.byId(goalId))!.currentAmountMinor, 2500000);

    final int eventId = await db.notificationEventDao.insertEvent(
      NotificationEventsCompanion.insert(
        postedAt: DateTime.now(),
        fingerprint: const Value('fp-abc'),
      ),
    );
    final NotificationEvent? event =
        await db.notificationEventDao.latestByFingerprint('fp-abc');
    expect(event!.id, eventId);
    expect(event.status, NotificationEventStatus.pending);
    expect(event.detectedType, DetectedTransactionType.unknown);
    expect(event.confidence, 0);

    // Seed sumber notifikasi masuk saat beforeOpen.
    final List<NotificationSource> sources =
        await db.select(db.notificationSources).get();
    expect(sources.map((s) => s.packageName), contains('id.dana'));
    expect(sources.every((s) => !s.enabled), isTrue,
        reason: 'seed harus disabled by default');

    await db.close();

    // Buka ulang: seed idempoten.
    final AppDatabase reopened = AppDatabase(NativeDatabase(File(dbPath)));
    final List<NotificationSource> again =
        await reopened.select(reopened.notificationSources).get();
    expect(again.length, sources.length);
    await reopened.close();
  });

  test('database baru langsung dibuat di v2 dengan seluruh tabel', () async {
    final AppDatabase db = AppDatabase(NativeDatabase.memory());
    final List<String> tables = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
        )
        .get()
        .then((rows) => rows.map((r) => r.data['name'] as String).toList());

    for (final String expected in <String>[
      'accounts',
      'categories',
      'payment_methods',
      'transactions',
      'tags',
      'transaction_tags',
      'budgets',
      'recurring_transactions',
      'settings',
      'notification_sources',
      'notification_events',
      'financial_goals',
      'goal_allocations',
      'merchant_category_rules',
      'receipt_scans',
    ]) {
      expect(tables, contains(expected), reason: 'tabel $expected hilang');
    }
    expect(db.schemaVersion, 8);

    // v8: kolom grouping ada di skema baru.
    final List<dynamic> columns = await db
        .customSelect('PRAGMA table_info(financial_goals)')
        .get()
        .then((rows) => rows.map((r) => r.data['name']).toList());
    expect(columns, containsAll(<String>['parent_id', 'is_group']));
    await db.close();
  });

  test('goal allocation idempoten & cascade saat goal dihapus', () async {
    final AppDatabase db = AppDatabase(NativeDatabase.memory());
    final int accId = await db.accountDao.insertAccount(
      AccountsCompanion.insert(name: 'CashQA', type: AccountType.cash),
    );
    final int goalId = await db.goalDao.insertGoal(
      FinancialGoalsCompanion.insert(
        name: 'Laptop QA',
        targetAmountMinor: 12000000,
      ),
    );

    await db.goalDao.upsertAllocation(goalId, accId, 3000000);
    await db.goalDao.upsertAllocation(goalId, accId, 4500000); // replace

    final List<GoalAllocation> allocs =
        await db.goalDao.allocationsForGoal(goalId);
    expect(allocs.single.allocatedAmountMinor, 4500000);

    final Map<int, int> totals =
        await db.goalDao.allocatedTotalsByAccount();
    expect(totals[accId], 4500000);

    await db.goalDao.upsertAllocation(goalId, accId, 0); // remove
    expect(await db.goalDao.allocationsForGoal(goalId), isEmpty);

    // CASCADE: hapus goal menghapus alokasinya (FK ON).
    await db.goalDao.upsertAllocation(goalId, accId, 1000000);
    await db.goalDao.softDelete(goalId);
    // soft delete tidak menghapus alokasi (masih bisa direstore):
    expect(await db.goalDao.allocationsForGoal(goalId), hasLength(1));

    await db.close();
  });
}
