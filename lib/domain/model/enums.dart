/// Enum domain yang dipersistenkan ke database via `intEnum`.
///
/// PENTING: nilai index disimpan ke SQLite. Jangan mengubah urutan
/// nilai enum yang sudah rilis — hanya boleh menambah di akhir.
library;

/// Jenis transaksi. Transfer tidak dihitung sebagai income/expense.
enum TransactionType { income, expense, transfer }

/// Tipe rekening/dompet.
///
/// SENGAJA DISEDERHANAKAN jadi HANYA 2 nilai (keputusan pengguna): tidak
/// ada lagi rekening per-bank/per-e-wallet — semua uang digital (mBanking,
/// DANA, GoPay, ShopeePay, OVO, dll) masuk ke SATU ember `nonCash`, dan
/// uang fisik masuk ke `cash`. Ini juga menyelesaikan ambiguitas lama:
/// sebelumnya transaksi hasil auto-catat notifikasi (`NotificationRepository`)
/// harus menebak rekening mana yang dituju kalau ada banyak rekening bank
/// terdaftar terpisah — sekarang tidak ada tebak-tebakan karena tujuannya
/// hanya bisa satu: `nonCash`.
///
/// `bank`/`ewallet`/`other` (nilai lama) DIHAPUS, bukan cuma dideprekasi —
/// aman karena migrasi skema yang menyertai perubahan ini (lihat
/// `AppDatabase.migration`) menghapus seluruh data rekening/transaksi lama
/// sekaligus (disetujui eksplisit oleh pengguna, tidak ada jalur upgrade
/// bertahap yang perlu menjaga kompatibilitas index enum lama).
enum AccountType { cash, nonCash }

/// Periode budget.
enum BudgetPeriod { daily, weekly, monthly, yearly }

/// Frekuensi transaksi berulang.
enum RecurrenceFrequency { daily, weekly, monthly, yearly }

/// Asal pencatatan transaksi. Append-only (index disimpan ke DB).
enum TxnSource {
  manual,
  notification,
  receiptScan,
  import,
  recurring,
  /// Penyesuaian saldo cepat dari widget layar utama (tombol +/-, kategori
  /// opsional via chip "Kategori"). Ditambahkan di akhir — jangan ubah
  /// urutan di atas.
  widget,
  /// Setor/tarik dana ke `FinancialGoal` (lihat `Transactions.goalId` dan
  /// `GoalRepository.contribute`/`withdraw`) — MEMOTONG/MENGEMBALIKAN
  /// saldo Tunai/Non Tunai sungguhan (earmark nyata, bukan pembukuan
  /// virtual — keputusan pengguna). Dikecualikan dari total
  /// income/expense laporan (lihat `TransactionDao._totalsQuery` &
  /// `watchFixedTotals`) supaya tidak dihitung dobel sebagai
  /// pemasukan/pengeluaran biasa, TAPI tetap muncul di riwayat transaksi
  /// biasa (tidak disembunyikan) supaya jejaknya terlihat.
  goalContribution,
}

/// Status pemrosesan satu event notifikasi Android.
enum NotificationEventStatus { recorded, pending, ignored, duplicate, failed }

/// Jenis yang terdeteksi parser notifikasi (sebelum normalisasi).
/// Refund/reversal tetap tercatat eksplisit di sini meskipun saat disimpan
/// sebagai transaksi dipetakan menjadi income + related_transaction_id.
enum DetectedTransactionType { income, expense, transfer, refund, reversal, unknown }

/// Siklus hidup tujuan tabungan.
enum GoalStatus { active, achieved, archived }

/// Status hasil scan nota.
enum ReceiptScanStatus { pending, saved, discarded }

extension TxnSourceX on TxnSource {
  String get label => switch (this) {
        TxnSource.manual => 'Manual',
        TxnSource.notification => 'Notifikasi',
        TxnSource.receiptScan => 'Scan Nota',
        TxnSource.import => 'Import',
        TxnSource.recurring => 'Berulang',
        TxnSource.widget => 'Widget Layar Utama',
        TxnSource.goalContribution => 'Tujuan Tabungan',
      };
}

extension NotificationEventStatusX on NotificationEventStatus {
  String get label => switch (this) {
        NotificationEventStatus.recorded => 'Tercatat',
        NotificationEventStatus.pending => 'Menunggu Review',
        NotificationEventStatus.ignored => 'Diabaikan',
        NotificationEventStatus.duplicate => 'Duplikat',
        NotificationEventStatus.failed => 'Gagal',
      };
}

extension DetectedTransactionTypeX on DetectedTransactionType {
  String get label => switch (this) {
        DetectedTransactionType.income => 'Pemasukan',
        DetectedTransactionType.expense => 'Pengeluaran',
        DetectedTransactionType.transfer => 'Transfer',
        DetectedTransactionType.refund => 'Refund',
        DetectedTransactionType.reversal => 'Reversal',
        DetectedTransactionType.unknown => 'Tidak dikenal',
      };

  /// Normalisasi ke jenis transaksi saat notifikasi DITERIMA sebagai
  /// transaksi (`NotificationRepository.acceptPending`). Transfer KELUAR
  /// dipetakan ke expense (uang keluar ke pihak luar, bukan perpindahan
  /// internal), refund/reversal ke income, unknown ke expense. Satu-satunya
  /// sumber kebenaran pemetaan ini — dipakai repo DAN bottom-sheet
  /// "Terima" supaya jenis yang ditampilkan ke pengguna selalu sama
  /// dengan yang disimpan.
  TransactionType get resolvedTransactionType => switch (this) {
        DetectedTransactionType.expense ||
        DetectedTransactionType.transfer ||
        DetectedTransactionType.unknown =>
          TransactionType.expense,
        DetectedTransactionType.income ||
        DetectedTransactionType.refund ||
        DetectedTransactionType.reversal =>
          TransactionType.income,
      };
}

extension GoalStatusX on GoalStatus {
  String get label => switch (this) {
        GoalStatus.active => 'Aktif',
        GoalStatus.achieved => 'Tercapai',
        GoalStatus.archived => 'Diarsipkan',
      };
}

extension RecurrenceFrequencyLabel on RecurrenceFrequency {
  String get shortLabel => switch (this) {
        RecurrenceFrequency.daily => 'Harian',
        RecurrenceFrequency.weekly => 'Mingguan',
        RecurrenceFrequency.monthly => 'Bulanan',
        RecurrenceFrequency.yearly => 'Tahunan',
      };
}

extension TransactionTypeX on TransactionType {
  String get label => switch (this) {
        TransactionType.income => 'Pemasukan',
        TransactionType.expense => 'Pengeluaran',
        TransactionType.transfer => 'Transfer',
      };

  /// Kategori hanya untuk income/expense — transfer tidak punya kategori.
  bool get supportsCategory => this != TransactionType.transfer;

  bool get supportsDestinationAccount => this == TransactionType.transfer;
}

extension AccountTypeX on AccountType {
  String get label => switch (this) {
        AccountType.cash => 'Tunai',
        AccountType.nonCash => 'Non Tunai',
      };
}

extension BudgetPeriodX on BudgetPeriod {
  String get label => switch (this) {
        BudgetPeriod.daily => 'Harian',
        BudgetPeriod.weekly => 'Mingguan',
        BudgetPeriod.monthly => 'Bulanan',
        BudgetPeriod.yearly => 'Tahunan',
      };
}

extension RecurrenceFrequencyX on RecurrenceFrequency {
  String get label => switch (this) {
        RecurrenceFrequency.daily => 'Setiap hari',
        RecurrenceFrequency.weekly => 'Setiap minggu',
        RecurrenceFrequency.monthly => 'Setiap bulan',
        RecurrenceFrequency.yearly => 'Setiap tahun',
      };
}
