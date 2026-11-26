import 'package:drift/drift.dart';

import '../../domain/model/enums.dart';
import 'dao/account_dao.dart';
import 'dao/budget_dao.dart';
import 'dao/category_dao.dart';
import 'dao/goal_dao.dart';
import 'dao/notification_dao.dart';
import 'dao/payment_method_dao.dart';
import 'dao/receipt_dao.dart';
import 'dao/recurring_dao.dart';
import 'dao/rule_dao.dart';
import 'dao/settings_dao.dart';
import 'dao/tag_dao.dart';
import 'dao/transaction_dao.dart';
import 'seed_data.dart';
import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Accounts,
    Categories,
    PaymentMethods,
    Transactions,
    Tags,
    TransactionTags,
    Budgets,
    RecurringTransactions,
    Settings,
    NotificationSources,
    NotificationEvents,
    FinancialGoals,
    GoalAllocations,
    MerchantCategoryRules,
    ReceiptScans,
  ],
  daos: [
    TransactionDao,
    CategoryDao,
    AccountDao,
    PaymentMethodDao,
    TagDao,
    BudgetDao,
    RecurringDao,
    SettingsDao,
    NotificationSourceDao,
    NotificationEventDao,
    GoalDao,
    RuleDao,
    ReceiptDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 8;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
        },
        onUpgrade: (Migrator m, int from, int to) async {
          // v1 -> v2: modul advanced (notifikasi, OCR, goals, rules).
          if (from < 2) {
            await m.addColumn(accounts, accounts.minBalanceMinor);
            await m.addColumn(transactions, transactions.source);
            await m.addColumn(transactions, transactions.merchant);
            await m.addColumn(transactions, transactions.fingerprint);
            await m.addColumn(
              transactions,
              transactions.relatedTransactionId,
            );
            await m.createTable(notificationSources);
            await m.createTable(notificationEvents);
            await m.createTable(financialGoals);
            await m.createTable(goalAllocations);
            await m.createTable(merchantCategoryRules);
            await m.createTable(receiptScans);
          }
          // v2 -> v3: model rekening disederhanakan jadi HANYA 2 ember
          // tetap — Tunai & Non Tunai (lihat dokumentasi `AccountType`).
          // `AccountType.bank`/`ewallet`/`other` DIHAPUS dari enum, jadi
          // baris `accounts` lama (dan semua yang mengacu ke accountId
          // lama: transaksi, budget, template berulang, goal allocation,
          // dst.) tidak punya arti lagi di model baru. Tidak ada
          // pemetaan otomatis yang aman (mis. rekening "BCA" + "GoPay"
          // lama harus digabung jadi satu "Non Tunai", tapi urutan &
          // riwayat transaksinya tidak bisa direkonstruksi begitu saja)
          // — PENGGUNA SUDAH SETUJU mulai bersih, jadi seluruh data
          // TRANSAKSIONAL dikosongkan di sini. Data KATALOG (kategori,
          // metode pembayaran, sumber notifikasi, pengaturan) TIDAK
          // disentuh — itu tidak bergantung pada struktur rekening lama.
          if (from < 3) {
            await delete(goalAllocations).go();
            await delete(financialGoals).go();
            await delete(merchantCategoryRules).go();
            await delete(receiptScans).go();
            await delete(notificationEvents).go();
            await delete(recurringTransactions).go();
            await delete(budgets).go();
            await delete(transactionTags).go();
            await delete(transactions).go();
            await delete(accounts).go();
          }
          // v3 -> v4: Goal Allocation diganti jadi "earmark nyata" —
          // setor/tarik dana ke goal sekarang benar-benar memotong/
          // mengembalikan saldo Tunai/Non Tunai lewat transaksi biasa
          // (lihat `GoalRepository.contribute`/`withdraw` dan dokumentasi
          // `TxnSource.goalContribution`). Kolom baru murni ADDITIVE
          // (nullable) — tidak perlu wipe data seperti v3.
          if (from < 4) {
            await m.addColumn(transactions, transactions.goalId);
          }
          // v4 -> v5: perbaiki package name sumber notifikasi "BCA mobile"
          // yang TERNYATA SALAH sejak awal ('com.bca' — bukan id package
          // Android yang valid, cuma tebakan best-effort, lihat komentar
          // di `seed_data.dart`). Ini sebabnya notifikasi dari aplikasi
          // myBCA tidak pernah terbaca sama sekali (packageName di
          // `NotificationCaptureService` tidak pernah cocok). Baris seed
          // hanya dibuat SEKALI saat tabel masih kosong (lihat
          // `ensureSeedData`), jadi instalasi yang sudah pernah dibuka
          // perlu di-UPDATE di sini secara eksplisit — mengganti
          // `seed_data.dart` saja tidak cukup untuk pengguna lama.
          // Dicocokkan lewat nilai LAMA yang salah (bukan appName, supaya
          // aman kalau pengguna sudah mengganti nama tampilannya sendiri)
          // — kalau baris itu sudah tidak ada/sudah diubah manual, UPDATE
          // ini sederhana tidak berpengaruh apa-apa (guard aman).
          if (from < 5) {
            await (update(notificationSources)
                  ..where(
                    (NotificationSources s) => s.packageName.equals('com.bca'),
                  ))
                .write(
              const NotificationSourcesCompanion(
                appName: Value('myBCA'),
                packageName: Value('com.bca.mybca.omni.android'),
              ),
            );
          }
          // v5 -> v6: notifikasi kustom per-budget — user dapat
          // mengaktifkan notifikasi pemakaian kategori (mis. jajan
          // harian) dan mengatur bebas judul + isi notifikasinya.
          // Kolom murni ADDITIVE (nullable / default false).
          if (from < 6) {
            await m.addColumn(budgets, budgets.alertEnabled);
            await m.addColumn(budgets, budgets.alertTitle);
            await m.addColumn(budgets, budgets.alertBody);
            await m.addColumn(budgets, budgets.alertLastSide);
          }
          // v6 -> v7: ambang NOMINAL pemicu notifikasi per-budget
          // (mis. peringatan dini di Rp100.000 walau batas Rp150.000).
          // NULL = batas budget itu sendiri = perilaku lama. v7 belum
          // pernah dirilis dalam build manapun, jadi blok ini final.
          if (from < 7) {
            await m.addColumn(budgets, budgets.alertThresholdMinor);
          }
          // v7 -> v8: GROUPING tabungan berjenjang. `parentId` menautkan
          // tujuan anak ke induk (NULL = root) dan `isGroup` menandai
          // node wadah yang totalnya murni roll-up anak. Murni ADDITIVE
          // (nullable + default false) — goal lama otomatis jadi root.
          // Catatan: saat from < 2, tabel financial_goals BARU dibuat
          // lewat from<2 di atas memakai skema terkini (sudah termasuk
          // parentId/isGroup) — addColumn di sini akan gagal "duplicate
          // column", jadi hanya dijalankan bila tabel memang sudah ada
          // sejak v2..v7. Index tetap perlu dibuat (createTable tidak
          // membuat index).
          if (from < 8) {
            if (from >= 2) {
              await m.addColumn(financialGoals, financialGoals.parentId);
              await m.addColumn(financialGoals, financialGoals.isGroup);
            }
            await m.createIndex(idxFinancialGoalsParent);
          }
        },
        beforeOpen: (OpeningDetails details) async {
          // Aktifkan enforcement foreign key (CASCADE dsb).
          await customStatement('PRAGMA foreign_keys = ON');
          await ensureSeedData();
        },
      );

  /// Idempoten: aman dipanggil berkali-kali, tidak pernah menduplikasi
  /// seed. Dipanggil saat onCreate dan bisa dipanggil ulang manual.
  Future<void> ensureSeedData() {
    return transaction(() async {
      if (await select(categories).get().then(
            (List<Category> list) => list.isEmpty,
          )) {
        for (final SeedCategory seed in kDefaultExpenseCategories) {
          await into(categories).insert(
            CategoriesCompanion.insert(
              name: seed.name,
              type: seed.type,
              icon: Value(seed.icon),
              colorValue: Value(seed.colorValue),
            ),
          );
        }
        for (final SeedCategory seed in kDefaultIncomeCategories) {
          await into(categories).insert(
            CategoriesCompanion.insert(
              name: seed.name,
              type: seed.type,
              icon: Value(seed.icon),
              colorValue: Value(seed.colorValue),
            ),
          );
        }
      }

      if (await select(paymentMethods).get().then(
            (List<PaymentMethod> list) => list.isEmpty,
          )) {
        for (final SeedPaymentMethod seed in kDefaultPaymentMethods) {
          await into(paymentMethods).insert(
            PaymentMethodsCompanion.insert(
              name: seed.name,
              icon: Value(seed.icon),
            ),
          );
        }
      }

      if (await select(accounts).get().then(
            (List<Account> list) => list.isEmpty,
          )) {
        for (final SeedAccount seed in kDefaultAccounts) {
          await into(accounts).insert(
            AccountsCompanion.insert(
              name: seed.name,
              type: seed.type,
              icon: Value(seed.icon),
              colorValue: Value(seed.colorValue),
              initialBalanceMinor: Value(seed.initialBalanceMinor),
            ),
          );
        }
      }

      if (await select(notificationSources).get().then(
            (List<NotificationSource> list) => list.isEmpty,
          )) {
        for (final SeedNotificationSource seed
            in kDefaultNotificationSources) {
          await into(notificationSources).insert(
            NotificationSourcesCompanion.insert(
              appName: seed.appName,
              packageName: seed.packageName,
              parserType: Value(seed.parserType),
            ),
          );
        }
      }

      // Settings: hanya isi key yang belum ada.
      final Map<String, String> existing = <String, String>{
        for (final Setting s in await settings.select().get()) s.key: s.value,
      };
      for (final MapEntry<String, String> entry
          in kDefaultSettings.entries) {
        if (!existing.containsKey(entry.key)) {
          await into(settings).insert(
            SettingsCompanion.insert(key: entry.key, value: entry.value),
          );
        }
      }

      // Guard tipe: kategori tidak boleh bertipe transfer.
      assert(() {
        final int bad = kDefaultExpenseCategories
            .followedBy(kDefaultIncomeCategories)
            .where((SeedCategory c) => c.type == TransactionType.transfer)
            .length;
        return bad == 0;
      }(), 'Kategori tidak boleh bertipe transfer');
    });
  }
}
